package apitypes

import "time"

// SessionState is the shared session status enum.
type SessionState string

const (
	StateConfirm SessionState = "confirm"
	StateWorking SessionState = "working"
	StateDone    SessionState = "done"
	StateIdle    SessionState = "idle"
)

// Priority: confirm > working > done > idle
func (s SessionState) Priority() int {
	switch s {
	case StateConfirm:
		return 4
	case StateWorking:
		return 3
	case StateDone:
		return 2
	case StateIdle:
		return 1
	default:
		return 0
	}
}

func (s SessionState) Valid() bool {
	switch s {
	case StateConfirm, StateWorking, StateDone, StateIdle:
		return true
	default:
		return false
	}
}

// Color maps product colors: red / yellow / green / empty.
func (s SessionState) Color() string {
	switch s {
	case StateConfirm:
		return "red"
	case StateWorking:
		return "yellow"
	case StateDone:
		return "green"
	default:
		return "empty"
	}
}

type Session struct {
	MachineID   string       `json:"machine_id"`
	MachineName string       `json:"machine_name,omitempty"`
	Agent       string       `json:"agent"` // codex | claude
	SessionID   string       `json:"session_id"`
	DisplayName string       `json:"display_name"`
	State       SessionState `json:"state"`
	Message     string       `json:"message,omitempty"`
	// Cwd is the full project path for the session (absolute when available).
	Cwd string `json:"cwd,omitempty"`
	// LastAssistantMessage is the latest agent-visible text (full, not truncated).
	LastAssistantMessage string `json:"last_assistant_message,omitempty"`
	// ParentSessionID links Codex subagent rows to their root session_id.
	// Empty means this row is a root session (shown in the main list).
	ParentSessionID string `json:"parent_session_id,omitempty"`
	// Source is the monitor channel that produced this session:
	// codex-file-watch | codex-file | claude-hook
	Source    string    `json:"source,omitempty"`
	UpdatedAt time.Time `json:"updated_at"`
	// StartedAt is set once when the session row is first inserted; not overwritten on upsert.
	StartedAt *time.Time `json:"started_at,omitempty"`
	// RealUsage is the session total tokens (input+output+reasoning+cache_write+cache_hit), filled on read.
	RealUsage int64 `json:"real_usage,omitempty"`
}

type ReportRequest struct {
	MachineID   string    `json:"machine_id"`
	MachineName string    `json:"machine_name"`
	Platform    string    `json:"platform"`          // linux | windows
	Version     string    `json:"version,omitempty"` // monitor binary version
	Sessions    []Session `json:"sessions"`
	ReportedAt  time.Time `json:"reported_at"`
}

type Machine struct {
	MachineID   string    `json:"machine_id"`
	MachineName string    `json:"machine_name"`
	Platform    string    `json:"platform"`
	Version     string    `json:"version,omitempty"` // last reported monitor version
	Online      bool      `json:"online"`
	LastSeenAt  time.Time `json:"last_seen_at"`
}

type HistoryEntry struct {
	MachineID   string       `json:"machine_id"`
	MachineName string       `json:"machine_name,omitempty"`
	Agent       string       `json:"agent"`
	SessionID   string       `json:"session_id"`
	DisplayName string       `json:"display_name,omitempty"`
	FromState   SessionState `json:"from_state,omitempty"`
	ToState     SessionState `json:"to_state"`
	Message     string       `json:"message,omitempty"`
	At          time.Time    `json:"at"`
}

type ErrorBody struct {
	Error ErrorDetail `json:"error"`
}

type ErrorDetail struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

// WSEvent is pushed over /api/v1/ws.
type WSEvent struct {
	Type    string      `json:"type"`
	Payload interface{} `json:"payload"`
}

const (
	WSSessionUpsert    = "session_upsert"
	WSSessionRemove    = "session_remove"
	WSNotification     = "notification"
	WSMachineOnline    = "machine_online"
	WSMachineOffline   = "machine_offline"
	WSError            = "error"
	WSMonitorCommand   = "monitor_command"   // server → monitor: leased command payload
	WSMonitorHello     = "monitor_hello"     // monitor → server (optional)
	WSCommandAvailable = "command_available" // optional notify
)

type NotificationPayload struct {
	MachineID   string `json:"machine_id"`
	MachineName string `json:"machine_name,omitempty"`
	Agent       string `json:"agent"`
	SessionID   string `json:"session_id"`
	DisplayName string `json:"display_name,omitempty"`
	// ParentSessionID mirrors Session so clients keep subagent hierarchy on notify path.
	ParentSessionID string       `json:"parent_session_id,omitempty"`
	State           SessionState `json:"state"`
	Color           string       `json:"color"`
	Message         string       `json:"message,omitempty"`
	At              time.Time    `json:"at"`
}
