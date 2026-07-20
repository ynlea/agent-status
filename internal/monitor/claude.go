package monitor

import (
	"bufio"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/ynlea/agent-status/pkg/apitypes"
)

// Claude session stale thresholds (no fresh hook UpdatedAt).
const (
	claudeWorkingStale = 45 * time.Minute
	claudeDoneStale    = 10 * time.Minute
	claudeConfirmStale = 30 * time.Minute
	claudeIdleDrop     = 24 * time.Hour
)

// ClaudeState persists session states written by hook subcommand.
type ClaudeState struct {
	mu   sync.Mutex
	path string
	// map session_id -> session
	Sessions map[string]apitypes.Session `json:"sessions"`
}

func LoadClaudeState(path string) (*ClaudeState, error) {
	cs := &ClaudeState{path: path, Sessions: map[string]apitypes.Session{}}
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return cs, nil
		}
		return nil, err
	}
	_ = json.Unmarshal(data, cs)
	if cs.Sessions == nil {
		cs.Sessions = map[string]apitypes.Session{}
	}
	return cs, nil
}

func (c *ClaudeState) saveLocked() error {
	if err := os.MkdirAll(filepath.Dir(c.path), 0o755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(c.path, data, 0o600)
}

// HookEvent is a minimal Claude Code hook stdin payload.
type HookEvent struct {
	HookEventName  string `json:"hook_event_name"`
	SessionID      string `json:"session_id"`
	Cwd            string `json:"cwd"`
	PermissionMode string `json:"permission_mode"`
	ToolName       string `json:"tool_name"`
	// Prompt fields (snake / camel variants appear across Claude Code versions)
	UserPrompt     string `json:"user_prompt"`
	Prompt         string `json:"prompt"`
	UserPromptAlt  string `json:"userPrompt"`
	TranscriptPath string `json:"transcript_path"`
	// NotificationType: permission_prompt | idle_prompt | auth_success | elicitation_dialog | ...
	NotificationType string `json:"notification_type"`
	Message          string `json:"message"`
	// Reason is present on Stop / SubagentStop (and some cancel paths).
	Reason string `json:"reason"`
}

// HookEventFromMap builds a HookEvent from a generic JSON object (flexible keys).
func HookEventFromMap(raw map[string]interface{}) HookEvent {
	ev := HookEvent{
		HookEventName:    firstString(raw, "hook_event_name", "hookEventName"),
		SessionID:        firstString(raw, "session_id", "sessionId"),
		Cwd:              firstString(raw, "cwd"),
		PermissionMode:   firstString(raw, "permission_mode", "permissionMode"),
		ToolName:         firstString(raw, "tool_name", "toolName"),
		UserPrompt:       firstString(raw, "user_prompt", "userPrompt", "prompt"),
		TranscriptPath:   firstString(raw, "transcript_path", "transcriptPath"),
		NotificationType: firstString(raw, "notification_type", "notificationType"),
		Message:          firstString(raw, "message"),
		Reason:           firstString(raw, "reason"),
	}
	// Keep Prompt as secondary alias if only camel was filled into UserPrompt via firstString.
	if ev.UserPrompt == "" {
		ev.Prompt = firstString(raw, "prompt")
	}
	return ev
}

func firstString(raw map[string]interface{}, keys ...string) string {
	for _, k := range keys {
		if v, ok := raw[k]; ok {
			if s, ok := v.(string); ok && strings.TrimSpace(s) != "" {
				return s
			}
		}
	}
	return ""
}

func (ev HookEvent) promptText() string {
	for _, s := range []string{ev.UserPrompt, ev.UserPromptAlt, ev.Prompt} {
		if strings.TrimSpace(s) != "" {
			return s
		}
	}
	if ev.TranscriptPath != "" {
		if s := lastPromptFromTranscript(ev.TranscriptPath); strings.TrimSpace(s) != "" {
			return s
		}
	}
	return ""
}

func applyNotificationState(hasPrev bool, prev apitypes.Session, msg string, ev HookEvent) (apitypes.SessionState, string) {
	nt := strings.ToLower(strings.TrimSpace(ev.NotificationType))
	body := strings.ToLower(ev.Message + " " + nt)

	// User cancelled / interrupted the turn — clear active state.
	if isCancelReason(ev.Message) || isCancelReason(nt) ||
		strings.Contains(body, "request interrupted") ||
		strings.Contains(body, "interrupted by user") {
		return apitypes.StateIdle, msg
	}

	// Prefer explicit notification_type. Do not treat idle "waiting for input" as confirm.
	needsConfirm := nt == "permission_prompt" ||
		nt == "elicitation_dialog" ||
		strings.Contains(nt, "permission") ||
		strings.Contains(nt, "elicitation") ||
		// Fallback only when type is empty: permission-ish wording in message.
		(nt == "" && (strings.Contains(body, "permission") ||
			strings.Contains(body, "approval") ||
			strings.Contains(body, "需要确认") ||
			(strings.Contains(body, "allow") && strings.Contains(body, "deny"))))

	if needsConfirm {
		if msg == "" {
			msg = "需要确认"
		}
		return apitypes.StateConfirm, msg
	}

	// idle_prompt / auth_success / unknown toast: preserve prior meaningful state.
	if hasPrev {
		switch prev.State {
		case apitypes.StateDone, apitypes.StateConfirm, apitypes.StateWorking, apitypes.StateIdle:
			return prev.State, msg
		}
	}
	// No prior state: idle toast alone is not "working".
	if nt == "idle_prompt" || strings.Contains(nt, "idle") {
		return apitypes.StateIdle, msg
	}
	return apitypes.StateWorking, msg
}

// lastPromptFromTranscript reads privacy-safe last user prompt from a Claude transcript jsonl.
func lastPromptFromTranscript(path string) string {
	f, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer f.Close()

	var last string
	sc := bufio.NewScanner(f)
	// transcripts can have long lines
	buf := make([]byte, 0, 64*1024)
	sc.Buffer(buf, 4*1024*1024)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" {
			continue
		}
		var row map[string]interface{}
		if json.Unmarshal([]byte(line), &row) != nil {
			continue
		}
		if t, _ := row["type"].(string); t == "last-prompt" {
			if p, ok := row["lastPrompt"].(string); ok && strings.TrimSpace(p) != "" {
				last = p
			}
			continue
		}
		if t, _ := row["type"].(string); t != "user" {
			continue
		}
		// skip tool results
		if _, ok := row["toolUseResult"]; ok {
			continue
		}
		msg, _ := row["message"].(map[string]interface{})
		if msg == nil {
			continue
		}
		if text := claudeMessageText(msg); text != "" {
			last = text
		}
	}
	return last
}

// lastAssistantFromTranscript returns the full text of the latest assistant message.
func lastAssistantFromTranscript(path string) string {
	if path == "" {
		return ""
	}
	f, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer f.Close()

	var last string
	sc := bufio.NewScanner(f)
	buf := make([]byte, 0, 64*1024)
	sc.Buffer(buf, 8*1024*1024)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" {
			continue
		}
		var row map[string]interface{}
		if json.Unmarshal([]byte(line), &row) != nil {
			continue
		}
		t, _ := row["type"].(string)
		msg, _ := row["message"].(map[string]interface{})
		role := ""
		if msg != nil {
			role, _ = msg["role"].(string)
		}
		if role == "" {
			role, _ = row["role"].(string)
		}
		if t != "assistant" && role != "assistant" {
			continue
		}
		if msg == nil {
			continue
		}
		if text := claudeMessageText(msg); text != "" {
			last = text
		}
	}
	return last
}

func claudeMessageText(msg map[string]interface{}) string {
	if msg == nil {
		return ""
	}
	switch c := msg["content"].(type) {
	case string:
		return strings.TrimSpace(c)
	case []interface{}:
		var parts []string
		for _, item := range c {
			m, ok := item.(map[string]interface{})
			if !ok {
				continue
			}
			typ, _ := m["type"].(string)
			if typ == "text" || typ == "output_text" || typ == "" {
				if txt, _ := m["text"].(string); strings.TrimSpace(txt) != "" {
					parts = append(parts, txt)
				}
			}
		}
		return strings.TrimSpace(strings.Join(parts, "\n"))
	default:
		return ""
	}
}

// ApplyHookEvent updates state from a hook event.
func (c *ClaudeState) ApplyHookEvent(ev HookEvent) (apitypes.Session, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if ev.SessionID == "" {
		ev.SessionID = "unknown"
	}
	prev, hasPrev := c.Sessions[ev.SessionID]

	cwd := strings.TrimSpace(ev.Cwd)
	if cwd == "" && hasPrev {
		cwd = prev.Cwd
	}
	display := ""
	if cwd != "" {
		display = filepath.Base(cwd)
	} else if hasPrev && prev.DisplayName != "" {
		display = prev.DisplayName
	} else {
		display = ev.SessionID
	}

	state := apitypes.StateWorking
	msg := ""
	lastAsst := ""
	if hasPrev {
		msg = prev.Message
		lastAsst = prev.LastAssistantMessage
	}
	// Drop leftover generic labels so UI never shows "stopped" as the task title.
	if isGenericStatusMessage(msg) {
		msg = ""
	}

	name := ev.HookEventName
	switch name {
	case "PermissionRequest":
		// Only red when the user may actually need to act. Auto modes still fire this hook
		// before tools; treating them as confirm causes false "待确认" mid-task.
		if permissionNeedsHuman(ev.PermissionMode) {
			state = apitypes.StateConfirm
			if msg == "" {
				msg = "需要确认"
			}
		} else if hasPrev && prev.State == apitypes.StateConfirm {
			state = apitypes.StateConfirm
		} else {
			state = apitypes.StateWorking
		}
	case "Notification":
		// Notification is overloaded: only permission/elicitation need red "confirm".
		// idle_prompt after a finished turn must NOT overwrite done → confirm.
		state, msg = applyNotificationState(hasPrev, prev, msg, ev)
	case "UserPromptSubmit":
		state = apitypes.StateWorking
		if sum := ShortSummary(ev.promptText(), defaultSummaryRunes); sum != "" {
			msg = sum
		}
	case "PreToolUse", "PostToolUse", "PostToolUseFailure":
		// Tool lifecycle means the agent is actively working (or just finished a tool).
		// Restores yellow after a brief/auto-approved PermissionRequest.
		state = apitypes.StateWorking
	case "Stop", "SubagentStop":
		// User cancel / interrupt should clear the active task, not look "done".
		if isCancelReason(ev.Reason) {
			state = apitypes.StateIdle
		} else {
			state = apitypes.StateDone
		}
		// Never write "stopped". Keep summary; if missing, try transcript once more.
		if msg == "" {
			if sum := ShortSummary(ev.promptText(), defaultSummaryRunes); sum != "" {
				msg = sum
			}
		}
	case "StopFailure":
		// API/stream failure ends the turn; do not leave a permanent working zombie.
		state = apitypes.StateIdle
		if msg == "" {
			if sum := ShortSummary(ev.Reason, defaultSummaryRunes); sum != "" {
				msg = sum
			} else if sum := ShortSummary(ev.promptText(), defaultSummaryRunes); sum != "" {
				msg = sum
			}
		}
	case "SessionStart":
		state = apitypes.StateIdle
		if !hasPrev {
			msg = ""
		}
	case "SessionEnd":
		state = apitypes.StateIdle
	default:
		// Unknown hooks must not permanently pin sessions as working.
		// Keep prior state when we have one (except still refresh summary if any).
		if hasPrev {
			state = prev.State
		} else {
			state = apitypes.StateWorking
		}
		if msg == "" {
			if sum := ShortSummary(ev.promptText(), defaultSummaryRunes); sum != "" {
				msg = sum
			}
		}
	}

	// Refresh full last assistant text from transcript when available.
	if asst := lastAssistantFromTranscript(ev.TranscriptPath); asst != "" {
		lastAsst = asst
	}

	sess := apitypes.Session{
		Agent:                "claude",
		SessionID:            ev.SessionID,
		DisplayName:          display,
		State:                state,
		Message:              msg,
		Cwd:                  cwd,
		LastAssistantMessage: lastAsst,
		Source:               "claude-hook",
		UpdatedAt:            time.Now().UTC(),
	}
	c.Sessions[ev.SessionID] = sess
	if err := c.saveLocked(); err != nil {
		return sess, err
	}
	return sess, nil
}

func (c *ClaudeState) List() []apitypes.Session {
	c.mu.Lock()
	defer c.mu.Unlock()
	now := time.Now().UTC()
	out := make([]apitypes.Session, 0, len(c.Sessions))
	for id, s := range c.Sessions {
		// Drop synthetic / ancient idle rows.
		if id == "test-sum" || id == "unknown" {
			delete(c.Sessions, id)
			continue
		}
		age := now.Sub(s.UpdatedAt)
		switch s.State {
		case apitypes.StateIdle:
			if age > claudeIdleDrop {
				delete(c.Sessions, id)
				continue
			}
		case apitypes.StateDone:
			// Brief green window, then clear.
			if age > claudeDoneStale {
				s.State = apitypes.StateIdle
				c.Sessions[id] = s
			}
		case apitypes.StateWorking:
			// No fresh hooks → treat as zombie (user cancel often skips Stop).
			if age > claudeWorkingStale {
				s.State = apitypes.StateIdle
				c.Sessions[id] = s
			}
		case apitypes.StateConfirm:
			if age > claudeConfirmStale {
				s.State = apitypes.StateIdle
				c.Sessions[id] = s
			}
		}
		out = append(out, s)
	}
	_ = c.saveLocked()
	return out
}

func isCancelReason(reason string) bool {
	r := strings.ToLower(strings.TrimSpace(reason))
	if r == "" {
		return false
	}
	for _, key := range []string{
		"interrupt", "interrupted", "cancel", "cancelled", "canceled",
		"abort", "aborted", "user_cancel", "user-cancel", "escape",
	} {
		if r == key || strings.Contains(r, key) {
			return true
		}
	}
	return false
}

// permissionNeedsHuman reports whether PermissionRequest may block on the user.
// Auto modes still emit this hook before tools — those must stay "working".
// Interactive modes mark confirm; PreToolUse/PostToolUse restore working when tools proceed.
func permissionNeedsHuman(mode string) bool {
	m := strings.ToLower(strings.TrimSpace(mode))
	m = strings.ReplaceAll(m, "_", "")
	m = strings.ReplaceAll(m, "-", "")
	switch m {
	case "bypasspermissions", "bypass",
		"acceptedits",
		"dontask", "allow", "auto":
		return false
	default:
		// default / ask / plan / empty / unknown → may need human
		return true
	}
}
