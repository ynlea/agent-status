package monitor

import (
	"bufio"
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/ynlea/agent-status/pkg/apitypes"
)

// pi working/idle thresholds (mirror the codex file scan, with a shorter
// working staleness so an ended session flips to idle faster).
const (
	piWorkingStale = 2 * time.Minute
	piIdleDrop     = 24 * time.Hour
	piIdleRevive   = 45 * time.Second
	// piExtTrustWindow bounds how long the realtime extension state is honored
	// after its last event; past it the scan falls back to local inference
	// (the extension may be gone / pi not running).
	piExtTrustWindow = 3 * time.Minute
)

// ScanPi walks the pi sessions root (~/.pi/agent/sessions) and derives one
// Session per jsonl file. Sessions are non-invasive: file format only, no
// hooks or extensions. Pure read; safe for concurrent calls.
func ScanPi(root string) ([]apitypes.Session, error) {
	if root == "" {
		return nil, nil
	}
	var sessions []apitypes.Session
	now := time.Now().UTC()
	ext := loadPiExtState()
	err := filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() {
			return nil
		}
		if !strings.HasSuffix(d.Name(), ".jsonl") {
			return nil
		}
		if s, ok := loadPiSession(path, now, ext); ok {
			sessions = append(sessions, s)
		}
		return nil
	})
	return sessions, err
}

// piSessionState accumulates the minimal per-file state during a stream read
// (first user message, last assistant text, last activity, session meta).
type piSessionState struct {
	sessionID     string
	cwd           string
	name          string
	firstUser     string
	lastAssistant string
	lastModel     string
	lastTime      time.Time
	fileMod       time.Time
}

func (s *piSessionState) applyLine(line string) {
	if line == "" {
		return
	}
	var rec map[string]interface{}
	if json.Unmarshal([]byte(line), &rec) != nil {
		return
	}
	if ts := parseTimeField(rec, "timestamp"); !ts.IsZero() && ts.After(s.lastTime) {
		s.lastTime = ts
	}
	switch typ, _ := rec["type"].(string); typ {
	case "session":
		if s.sessionID == "" {
			s.sessionID = strField(rec, "id")
		}
		if s.cwd == "" {
			s.cwd = strField(rec, "cwd")
		}
	case "session_info":
		if s.name == "" {
			s.name = strings.TrimSpace(strField(rec, "name"))
		}
	case "message":
		msg := mapField(rec, "message")
		if msg == nil {
			return
		}
		switch strField(msg, "role") {
		case "user":
			if s.firstUser == "" {
				s.firstUser = piTextContent(msg["content"])
			}
		case "assistant":
			if text := piTextContent(msg["content"]); text != "" {
				s.lastAssistant = text
			}
			if m := strField(msg, "model"); m != "" {
				s.lastModel = m
			}
		}
	}
}

// piTextContent joins text blocks from a pi message content field
// (string or typed blocks; thinking/toolCall blocks are skipped).
func piTextContent(content interface{}) string {
	switch c := content.(type) {
	case string:
		return strings.TrimSpace(c)
	case []interface{}:
		var parts []string
		for _, item := range c {
			block, ok := item.(map[string]interface{})
			if !ok {
				continue
			}
			if typ, _ := block["type"].(string); typ == "text" {
				if t := strings.TrimSpace(strField(block, "text")); t != "" {
					parts = append(parts, t)
				}
			}
		}
		return strings.TrimSpace(strings.Join(parts, " "))
	}
	return ""
}

// loadPiSession streams one pi session file, keeping only the state ScanPi
// needs; a 600KB+ file is read line-by-line and discarded, not held in memory.
func loadPiSession(path string, now time.Time, ext map[string]*piExtSessionState) (apitypes.Session, bool) {
	f, err := os.Open(path)
	if err != nil {
		return apitypes.Session{}, false
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil {
		return apitypes.Session{}, false
	}
	fileMod := info.ModTime().UTC()
	st := piSessionState{fileMod: fileMod}
	r := bufio.NewReader(f)
	for {
		line, err := r.ReadString('\n')
		if len(line) > 0 {
			st.applyLine(strings.TrimSpace(line))
		}
		if err == io.EOF {
			break
		}
		if err != nil {
			return apitypes.Session{}, false
		}
	}
	// Look the extension state up by the header session id (authoritative),
	// not the file name, so header/file-name mismatches still coordinate.
	return st.session(path, fileMod, now, ext[st.sessionID])
}

func (s piSessionState) session(path string, fileMod, now time.Time, ext *piExtSessionState) (apitypes.Session, bool) {
	if s.sessionID == "" {
		return apitypes.Session{}, false
	}
	anchor := fileMod
	if !s.lastTime.IsZero() {
		anchor = s.lastTime
	}
	state := apitypes.StateIdle
	if now.Sub(anchor) <= piWorkingStale {
		state = apitypes.StateWorking
	}
	// Idle session whose file was just written again flips back to working
	// immediately (mirrors the codex scan) so a brief activity gap between
	// ticks does not leave a stale idle state.
	if state == apitypes.StateIdle && now.Sub(fileMod) <= piIdleRevive {
		state = apitypes.StateWorking
	}
	display := s.name
	if display == "" {
		if s.firstUser != "" {
			display = ShortSummary(s.firstUser, defaultSummaryRunes)
		} else {
			display = strings.TrimSuffix(filepath.Base(path), ".jsonl")
		}
	}
	message := ""
	if state == apitypes.StateWorking {
		if s.firstUser != "" {
			message = ShortSummary(s.firstUser, defaultSummaryRunes)
		} else if s.lastAssistant != "" {
			message = ShortSummary(s.lastAssistant, defaultSummaryRunes)
		}
	}
	// A fresh realtime extension state overrides the inference: when the
	// extension reported idle (agent_settled / session_shutdown) the scan
	// must not flip the session back to working within the staleness window.
	if ext != nil && !ext.UpdatedAt.IsZero() && now.Sub(ext.UpdatedAt) <= piExtTrustWindow {
		state = ext.State
		if ext.Message != "" {
			message = ext.Message
		}
		if ext.DisplayName != "" {
			display = ext.DisplayName
		}
		if ext.Cwd != "" {
			s.cwd = ext.Cwd
		}
		anchor = ext.UpdatedAt
	} else {
		// Stale idle sessions are dropped entirely (same policy as codex scan);
		// ext-managed sessions are exempt (the extension keeps them alive).
		if state == apitypes.StateIdle && now.Sub(anchor) > piIdleDrop {
			return apitypes.Session{}, false
		}
	}
	return apitypes.Session{
		Agent:                "pi",
		SessionID:            s.sessionID,
		DisplayName:          display,
		State:                state,
		Message:              message,
		Cwd:                  s.cwd,
		LastAssistantMessage: s.lastAssistant,
		Source:               "pi-file",
		UpdatedAt:            anchor.UTC(),
	}, true
}

// piExtSessionState is one session's realtime state written by the pi
// extension (~/.agent-status/pi-ext-state.json). It is the coordination
// channel between the live extension and the file scan.
type piExtSessionState struct {
	State       apitypes.SessionState `json:"state"`
	UpdatedAt   time.Time             `json:"updated_at"`
	DisplayName string                `json:"display_name,omitempty"`
	Cwd         string                `json:"cwd,omitempty"`
	Message     string                `json:"message,omitempty"`
}

func piExtStatePath() string {
	if home, err := os.UserHomeDir(); err == nil {
		return filepath.Join(home, ".agent-status", "pi-ext-state.json")
	}
	return "pi-ext-state.json"
}

// loadPiExtState reads the extension state file. Returns nil when absent or
// malformed, so the scan degrades gracefully to pure file inference.
func loadPiExtState() map[string]*piExtSessionState {
	raw, err := os.ReadFile(piExtStatePath())
	if err != nil {
		return nil
	}
	var st struct {
		Sessions map[string]*piExtSessionState `json:"sessions"`
	}
	if json.Unmarshal(raw, &st) != nil || len(st.Sessions) == 0 {
		return nil
	}
	return st.Sessions
}
