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

// ScanCodex walks rollout-*.jsonl under sessions root and derives session states
// from structured Codex events (task_started / task_complete / tool calls).
func ScanCodex(root string) ([]apitypes.Session, error) {
	if root == "" {
		return nil, nil
	}
	var out []apitypes.Session
	err := filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() {
			return nil
		}
		base := d.Name()
		if !strings.HasPrefix(base, "rollout-") || !strings.HasSuffix(base, ".jsonl") {
			return nil
		}
		if sess, ok := parseCodexRollout(path); ok {
			out = append(out, sess)
		}
		return nil
	})
	return out, err
}

type codexLine struct {
	Timestamp string          `json:"timestamp"`
	Type      string          `json:"type"`
	Payload   json.RawMessage `json:"payload"`
}

type codexRolloutState struct {
	sessionID string
	display   string
	state     apitypes.SessionState
	message   string
	lastEvent time.Time
	cwd       string
}

func newCodexRolloutState(path string) codexRolloutState {
	sessionID := strings.TrimSuffix(strings.TrimPrefix(filepath.Base(path), "rollout-"), ".jsonl")
	display := sessionID
	if len(display) > 24 {
		display = display[:24]
	}
	return codexRolloutState{
		sessionID: sessionID,
		display:   display,
		state:     apitypes.StateIdle,
	}
}

func (s *codexRolloutState) applyLine(line string, fallback time.Time) {
	if line == "" {
		return
	}
	var row codexLine
	if json.Unmarshal([]byte(line), &row) != nil {
		return
	}
	ts := parseCodexTime(row.Timestamp)
	if ts.IsZero() {
		ts = fallback
	}

	var payload map[string]interface{}
	_ = json.Unmarshal(row.Payload, &payload)
	if payload == nil {
		payload = map[string]interface{}{}
	}
	pt, _ := payload["type"].(string)

	if c, ok := payload["cwd"].(string); ok && c != "" {
		s.cwd = c
	}
	if tsMap, ok := payload["thread_settings"].(map[string]interface{}); ok {
		if c, ok := tsMap["cwd"].(string); ok && c != "" {
			s.cwd = c
		}
	}

	switch pt {
	case "task_started":
		s.state = apitypes.StateWorking
		s.message = preferMessage(s.message, "task_started")
		s.lastEvent = ts
	case "user_message":
		s.state = apitypes.StateWorking
		if sum := ShortSummary(extractCodexUserText(payload), defaultSummaryRunes); sum != "" {
			s.message = sum
		} else {
			s.message = preferMessage(s.message, "user_message")
		}
		s.lastEvent = ts
	case "custom_tool_call", "function_call", "mcp_tool_call", "exec_command_begin", "patch_apply_begin":
		if s.state != apitypes.StateConfirm {
			s.state = apitypes.StateWorking
			s.message = preferMessage(s.message, shortToolMsg(pt, payload))
		}
		s.lastEvent = ts
	case "custom_tool_call_output", "function_call_output", "reasoning", "agent_message":
		if s.state != apitypes.StateConfirm {
			s.state = apitypes.StateWorking
			s.message = preferMessage(s.message, pt)
		}
		s.lastEvent = ts
	case "task_complete":
		s.state = apitypes.StateDone
		s.message = preferMessage(s.message, "task_complete")
		s.lastEvent = ts
	case "turn_aborted":
		s.state = apitypes.StateIdle
		s.message = preferMessage(s.message, "turn_aborted")
		s.lastEvent = ts
	case "exec_approval_request", "apply_patch_approval_request", "request_user_input",
		"user_input_request", "elicitation_request":
		s.state = apitypes.StateConfirm
		s.message = preferMessage(s.message, pt)
		s.lastEvent = ts
	default:
		if isConfirmEvent(row.Type, pt, payload) {
			s.state = apitypes.StateConfirm
			label := pt
			if label == "" {
				label = row.Type
			}
			s.message = preferMessage(s.message, label)
			s.lastEvent = ts
		}
	}
}

// extractCodexUserText pulls a short user-visible string from Codex event payloads.
func extractCodexUserText(payload map[string]interface{}) string {
	for _, key := range []string{"message", "text", "content", "prompt", "input"} {
		if v, ok := payload[key]; ok {
			if s := stringifyCodexText(v); s != "" {
				return s
			}
		}
	}
	if msg, ok := payload["message"].(map[string]interface{}); ok {
		for _, key := range []string{"content", "text"} {
			if s := stringifyCodexText(msg[key]); s != "" {
				return s
			}
		}
	}
	return ""
}

func stringifyCodexText(v interface{}) string {
	switch t := v.(type) {
	case string:
		return t
	case []interface{}:
		var parts []string
		for _, item := range t {
			switch el := item.(type) {
			case string:
				if el != "" {
					parts = append(parts, el)
				}
			case map[string]interface{}:
				if txt, ok := el["text"].(string); ok && txt != "" {
					parts = append(parts, txt)
				} else if txt, ok := el["content"].(string); ok && txt != "" {
					parts = append(parts, txt)
				}
			}
		}
		return strings.Join(parts, " ")
	default:
		return ""
	}
}

func (s codexRolloutState) session(fileMod, now time.Time) (apitypes.Session, bool) {
	if s.sessionID == "" {
		return apitypes.Session{}, false
	}
	display := s.display
	if s.cwd != "" {
		display = filepath.Base(s.cwd)
	}
	state := s.state
	message := s.message
	anchor := fileMod
	if !s.lastEvent.IsZero() {
		anchor = s.lastEvent
	}
	switch state {
	case apitypes.StateDone:
		if now.Sub(anchor) > 10*time.Minute {
			state = apitypes.StateIdle
			message = ""
		}
	case apitypes.StateWorking:
		if now.Sub(anchor) > 5*time.Minute {
			state = apitypes.StateIdle
			message = ""
		}
	case apitypes.StateConfirm:
		if now.Sub(anchor) > 30*time.Minute {
			state = apitypes.StateIdle
			message = ""
		}
	case apitypes.StateIdle:
		if now.Sub(fileMod) < 45*time.Second {
			state = apitypes.StateWorking
		}
	}
	if state == apitypes.StateIdle && now.Sub(fileMod) > 24*time.Hour {
		return apitypes.Session{}, false
	}
	updated := fileMod
	if !s.lastEvent.IsZero() {
		updated = s.lastEvent.UTC()
	}
	return apitypes.Session{
		Agent:       "codex",
		SessionID:   s.sessionID,
		DisplayName: display,
		State:       state,
		Message:     message,
		Source:      "codex-file",
		UpdatedAt:   updated,
	}, true
}

func loadCodexRollout(path string) (codexRolloutState, int64, apitypes.Session, bool) {
	f, err := os.Open(path)
	if err != nil {
		return codexRolloutState{}, 0, apitypes.Session{}, false
	}
	defer f.Close()

	var lines []string
	reader := bufio.NewReaderSize(f, 64*1024)
	var offset int64
	for {
		line, readErr := reader.ReadString('\n')
		if len(line) > 0 && strings.HasSuffix(line, "\n") {
			offset += int64(len(line))
			line = strings.TrimSuffix(line, "\n")
			line = strings.TrimSuffix(line, "\r")
			if line != "" {
				lines = append(lines, line)
				if len(lines) > 200 {
					lines = lines[1:]
				}
			}
		}
		if readErr == io.EOF {
			break
		}
		if readErr != nil {
			return codexRolloutState{}, 0, apitypes.Session{}, false
		}
	}
	if len(lines) == 0 {
		return newCodexRolloutState(path), offset, apitypes.Session{}, false
	}

	fi, _ := os.Stat(path)
	fileMod := time.Now().UTC()
	if fi != nil {
		fileMod = fi.ModTime().UTC()
	}
	state := newCodexRolloutState(path)
	for _, line := range lines {
		state.applyLine(line, fileMod)
	}
	session, ok := state.session(fileMod, time.Now().UTC())
	return state, offset, session, ok
}

func parseCodexRollout(path string) (apitypes.Session, bool) {
	_, _, session, ok := loadCodexRollout(path)
	return session, ok
}

// shortToolMsg is a privacy-safe label (event type + optional tool name), never prompt text.
func shortToolMsg(pt string, payload map[string]interface{}) string {
	if name, ok := payload["name"].(string); ok && name != "" {
		// keep short
		if len(name) > 40 {
			name = name[:40]
		}
		return pt + ":" + name
	}
	return pt
}

func isConfirmEvent(outerType, payloadType string, payload map[string]interface{}) bool {
	for _, t := range []string{outerType, payloadType} {
		lt := strings.ToLower(t)
		if strings.Contains(lt, "approval_request") ||
			strings.Contains(lt, "request_user_input") ||
			lt == "user_input_request" ||
			strings.Contains(lt, "elicitation_request") {
			return true
		}
	}
	if name, ok := payload["name"].(string); ok {
		ln := strings.ToLower(name)
		if strings.Contains(ln, "request_user_input") {
			return true
		}
	}
	return false
}

func parseCodexTime(s string) time.Time {
	if s == "" {
		return time.Time{}
	}
	if t, err := time.Parse(time.RFC3339Nano, s); err == nil {
		return t
	}
	if t, err := time.Parse(time.RFC3339, s); err == nil {
		return t
	}
	return time.Time{}
}
