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
	var items []codexSessionItem
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
		if item, ok := parseCodexRolloutItem(path); ok {
			items = append(items, item)
		}
		return nil
	})
	return finalizeCodexSessions(items), err
}

// codexSessionItem is one rollout file's derived session plus thread meta for parent attach.
type codexSessionItem struct {
	sess           apitypes.Session
	threadID       string
	parentThreadID string
	isSubagent     bool
}

// finalizeCodexSessions attaches parent_session_id then folds root states.
// Scan and file-watch Snapshot share this path so hierarchy does not drift.
func finalizeCodexSessions(items []codexSessionItem) []apitypes.Session {
	return foldCodexRootStates(attachCodexParents(items))
}

// attachCodexParents maps subagent parent_thread_id → root reported SessionID (filename stem).
func attachCodexParents(items []codexSessionItem) []apitypes.Session {
	threadToReported := make(map[string]string, len(items))
	for _, it := range items {
		if !it.isSubagent && it.threadID != "" {
			threadToReported[it.threadID] = it.sess.SessionID
		}
	}
	out := make([]apitypes.Session, 0, len(items))
	for _, it := range items {
		s := it.sess
		if it.isSubagent {
			parentKey := it.parentThreadID
			if mapped, ok := threadToReported[parentKey]; ok {
				s.ParentSessionID = mapped
			} else if parentKey != "" {
				// Parent rollout missing: still non-root so main list hides orphans.
				s.ParentSessionID = parentKey
			} else if it.threadID != "" {
				s.ParentSessionID = it.threadID
			} else {
				s.ParentSessionID = s.SessionID
			}
		}
		out = append(out, s)
	}
	return out
}

// foldCodexRootStates raises root state/updated_at from its children (confirm > working > done > idle).
// Child rows keep their own state for detail view.
func foldCodexRootStates(sessions []apitypes.Session) []apitypes.Session {
	if len(sessions) == 0 {
		return sessions
	}
	childrenByParent := make(map[string][]int)
	for i, s := range sessions {
		if s.ParentSessionID == "" {
			continue
		}
		childrenByParent[s.ParentSessionID] = append(childrenByParent[s.ParentSessionID], i)
	}
	if len(childrenByParent) == 0 {
		return sessions
	}
	out := make([]apitypes.Session, len(sessions))
	copy(out, sessions)
	for i := range out {
		root := &out[i]
		if root.ParentSessionID != "" {
			continue
		}
		kids := childrenByParent[root.SessionID]
		if len(kids) == 0 {
			continue
		}
		best := root.State
		latest := root.UpdatedAt
		var childHint string
		for _, ci := range kids {
			ch := sessions[ci]
			if ch.State.Priority() > best.Priority() {
				best = ch.State
			}
			if ch.UpdatedAt.After(latest) {
				latest = ch.UpdatedAt
			}
			if childHint == "" {
				name := strings.TrimSpace(ch.DisplayName)
				if name != "" {
					childHint = name
				}
			}
		}
		root.State = best
		if !latest.IsZero() {
			root.UpdatedAt = latest
		}
		if strings.TrimSpace(root.Message) == "" && childHint != "" {
			root.Message = "子任务: " + childHint
		}
	}
	return out
}

type codexLine struct {
	Timestamp string          `json:"timestamp"`
	Type      string          `json:"type"`
	Payload   json.RawMessage `json:"payload"`
}

type codexRolloutState struct {
	sessionID     string
	display       string
	state         apitypes.SessionState
	message       string
	lastAssistant string
	lastEvent     time.Time
	cwd           string
	// Thread meta from session_meta (parent attach / subagent display).
	threadID       string
	parentThreadID string
	isSubagent     bool
	agentNickname  string
	agentPath      string
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

	// session_meta is usually the first line; fields live on the payload itself.
	if row.Type == "session_meta" || pt == "session_meta" {
		s.applySessionMeta(payload)
		return
	}

	if c, ok := payload["cwd"].(string); ok && c != "" {
		s.cwd = c
	}
	if tsMap, ok := payload["thread_settings"].(map[string]interface{}); ok {
		if c, ok := tsMap["cwd"].(string); ok && c != "" {
			s.cwd = c
		}
	}

	// Full assistant message body when present (response_item / event shapes).
	if text := extractCodexAssistantText(row.Type, pt, payload); text != "" {
		s.lastAssistant = text
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
			// Prefer real assistant text already captured; keep event label only as fallback.
			if s.lastAssistant == "" {
				s.message = preferMessage(s.message, pt)
			}
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
				typ, _ := el["type"].(string)
				if typ == "output_text" || typ == "text" || typ == "input_text" || typ == "" {
					if txt, ok := el["text"].(string); ok && txt != "" {
						parts = append(parts, txt)
					} else if txt, ok := el["content"].(string); ok && txt != "" {
						parts = append(parts, txt)
					}
				} else if txt, ok := el["text"].(string); ok && txt != "" {
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

// applySessionMeta extracts thread hierarchy and display hints from Codex session_meta.
func (s *codexRolloutState) applySessionMeta(payload map[string]interface{}) {
	if payload == nil {
		return
	}
	if id, ok := payload["id"].(string); ok && strings.TrimSpace(id) != "" {
		s.threadID = strings.TrimSpace(id)
	}
	if cwd, ok := payload["cwd"].(string); ok && cwd != "" {
		s.cwd = cwd
	}
	if nick, ok := payload["agent_nickname"].(string); ok && strings.TrimSpace(nick) != "" {
		s.agentNickname = strings.TrimSpace(nick)
	}
	if path, ok := payload["agent_path"].(string); ok && strings.TrimSpace(path) != "" {
		s.agentPath = strings.TrimSpace(path)
	}

	parent := ""
	if v, ok := payload["parent_thread_id"].(string); ok {
		parent = strings.TrimSpace(v)
	}
	if parent == "" {
		if v, ok := payload["forked_from_id"].(string); ok {
			parent = strings.TrimSpace(v)
		}
	}
	// Nested source.subagent.thread_spawn also carries parent / nickname / path.
	if src, ok := payload["source"].(map[string]interface{}); ok {
		if sub, ok := src["subagent"].(map[string]interface{}); ok {
			s.isSubagent = true
			spawn, _ := sub["thread_spawn"].(map[string]interface{})
			if spawn == nil {
				spawn = sub
			}
			if parent == "" {
				if v, ok := spawn["parent_thread_id"].(string); ok {
					parent = strings.TrimSpace(v)
				}
			}
			if s.agentNickname == "" {
				if v, ok := spawn["agent_nickname"].(string); ok {
					s.agentNickname = strings.TrimSpace(v)
				}
			}
			if s.agentPath == "" {
				if v, ok := spawn["agent_path"].(string); ok {
					s.agentPath = strings.TrimSpace(v)
				}
			}
		}
	}
	if parent != "" {
		s.parentThreadID = parent
		s.isSubagent = true
	}
	if ts, ok := payload["thread_source"].(string); ok && strings.EqualFold(strings.TrimSpace(ts), "subagent") {
		s.isSubagent = true
	}
}

func (s codexRolloutState) session(fileMod, now time.Time) (apitypes.Session, bool) {
	if s.sessionID == "" {
		return apitypes.Session{}, false
	}
	// Subagent display prefers nickname, then agent_path base; roots keep cwd base.
	display := s.display
	if s.agentNickname != "" {
		display = s.agentNickname
	} else if s.agentPath != "" {
		display = filepath.Base(s.agentPath)
	} else if s.cwd != "" {
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
		Agent:                "codex",
		SessionID:            s.sessionID,
		DisplayName:          display,
		State:                state,
		Message:              message,
		Cwd:                  s.cwd,
		LastAssistantMessage: s.lastAssistant,
		Source:               "codex-file",
		UpdatedAt:            updated,
	}, true
}

func (s codexRolloutState) toItem(sess apitypes.Session) codexSessionItem {
	return codexSessionItem{
		sess:           sess,
		threadID:       s.threadID,
		parentThreadID: s.parentThreadID,
		isSubagent:     s.isSubagent,
	}
}

// extractCodexAssistantText returns full assistant-visible text from a rollout line.
func extractCodexAssistantText(rowType, payloadType string, payload map[string]interface{}) string {
	if payload == nil {
		return ""
	}
	// response_item / message with assistant role
	role, _ := payload["role"].(string)
	typ := payloadType
	if typ == "" {
		typ, _ = payload["type"].(string)
	}
	if role == "assistant" || typ == "agent_message" || (rowType == "response_item" && role == "assistant") {
		if text := extractCodexUserText(payload); text != "" {
			// reuse text extractor for content/text fields
			return strings.TrimSpace(text)
		}
		// content blocks often use output_text
		if text := stringifyCodexText(payload["content"]); text != "" {
			return strings.TrimSpace(text)
		}
		if msg, ok := payload["message"].(string); ok && strings.TrimSpace(msg) != "" {
			return strings.TrimSpace(msg)
		}
		if msg, ok := payload["message"].(map[string]interface{}); ok {
			if text := stringifyCodexText(msg["content"]); text != "" {
				return strings.TrimSpace(text)
			}
		}
	}
	// event_msg agent_message with free text
	if rowType == "event_msg" && payloadType == "agent_message" {
		if text := extractCodexUserText(payload); text != "" {
			return strings.TrimSpace(text)
		}
	}
	return ""
}

func loadCodexRollout(path string) (codexRolloutState, int64, apitypes.Session, bool) {
	f, err := os.Open(path)
	if err != nil {
		return codexRolloutState{}, 0, apitypes.Session{}, false
	}
	defer f.Close()

	// Keep session_meta (usually line 1) plus a trailing event window so large
	// rollouts still attach parent hierarchy without replaying entire history.
	var metaLines []string
	var recent []string
	reader := bufio.NewReaderSize(f, 64*1024)
	var offset int64
	for {
		line, readErr := reader.ReadString('\n')
		if len(line) > 0 && strings.HasSuffix(line, "\n") {
			offset += int64(len(line))
			line = strings.TrimSuffix(line, "\n")
			line = strings.TrimSuffix(line, "\r")
			if line != "" {
				if strings.Contains(line, `"session_meta"`) {
					metaLines = append(metaLines, line)
				} else {
					recent = append(recent, line)
					if len(recent) > 200 {
						recent = recent[1:]
					}
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
	if len(metaLines) == 0 && len(recent) == 0 {
		return newCodexRolloutState(path), offset, apitypes.Session{}, false
	}

	fi, _ := os.Stat(path)
	fileMod := time.Now().UTC()
	if fi != nil {
		fileMod = fi.ModTime().UTC()
	}
	state := newCodexRolloutState(path)
	for _, line := range metaLines {
		state.applyLine(line, fileMod)
	}
	for _, line := range recent {
		state.applyLine(line, fileMod)
	}
	session, ok := state.session(fileMod, time.Now().UTC())
	return state, offset, session, ok
}

func parseCodexRollout(path string) (apitypes.Session, bool) {
	_, _, session, ok := loadCodexRollout(path)
	return session, ok
}

func parseCodexRolloutItem(path string) (codexSessionItem, bool) {
	state, _, session, ok := loadCodexRollout(path)
	if !ok {
		return codexSessionItem{}, false
	}
	return state.toItem(session), true
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
