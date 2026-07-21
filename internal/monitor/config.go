package monitor

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

type Config struct {
	ServerURL   string `json:"server_url"`
	Key         string `json:"key"`
	MachineID   string `json:"machine_id"`
	MachineName string `json:"machine_name"`
	Platform    string `json:"platform"` // linux|windows; auto if empty
	// CodexSessionsDir overrides default ~/.codex/sessions
	CodexSessionsDir string `json:"codex_sessions_dir,omitempty"`
	// StateFile stores Claude hook session map
	StateFile string `json:"state_file,omitempty"`
	// ReportIntervalSec heartbeat when no changes
	ReportIntervalSec int `json:"report_interval_sec,omitempty"`
	// CodexFileWatch enables real-time watching of ordinary Codex rollout files (default true).
	// A periodic full scan remains enabled to recover from missed filesystem events.
	CodexFileWatch *bool `json:"codex_file_watch,omitempty"`

	// UsageEnabled turns on local token usage scan/report (default true).
	UsageEnabled *bool `json:"usage_enabled,omitempty"`
	// ClaudeProjectsDir overrides default ~/.claude/projects
	ClaudeProjectsDir string `json:"claude_projects_dir,omitempty"`
	// UsageStateFile stores usage file cursors (default ~/.agent-status/usage-cursors.json)
	UsageStateFile string `json:"usage_state_file,omitempty"`
	// UsageIntervalSec is how often to tick usage reconciliation (default 60).
	// Unchanged files only get Stat; open/parse happens only when size grows.
	UsageIntervalSec int `json:"usage_interval_sec,omitempty"`
	// UsageDiscoverSec is how often to walk trees for new usage files (default 600).
	// Keep this slower than UsageIntervalSec so 1-minute ticks stay cheap.
	UsageDiscoverSec int `json:"usage_discover_sec,omitempty"`

	// CcSwitchDB overrides default ~/.cc-switch/cc-switch.db
	CcSwitchDB string `json:"cc_switch_db,omitempty"`
	// CcSwitchBin is the cc-switch executable (default: cc-switch on PATH)
	CcSwitchBin string `json:"cc_switch_bin,omitempty"`
	// CommandPollSec is how often to pull remote commands (default 5). 0 disables.
	CommandPollSec int `json:"command_poll_sec,omitempty"`
	// ProviderReportSec is how often to push provider snapshots (default = report_interval_sec).
	ProviderReportSec int `json:"provider_report_sec,omitempty"`
}

func (c *Config) UsageScanEnabled() bool {
	if c.UsageEnabled == nil {
		return true
	}
	return *c.UsageEnabled
}

func (c *Config) FileWatchEnabled() bool {
	if c.CodexFileWatch == nil {
		return true
	}
	return *c.CodexFileWatch
}

func LoadConfig(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	// Strip UTF-8 BOM written by some Windows editors / PowerShell 5.1 UTF8.
	data = bytes.TrimPrefix(data, []byte{0xEF, 0xBB, 0xBF})
	var c Config
	if err := json.Unmarshal(data, &c); err != nil {
		return nil, fmt.Errorf("parse config: %w", err)
	}
	if c.ServerURL == "" || c.Key == "" {
		return nil, fmt.Errorf("server_url and key are required")
	}
	if c.MachineName == "" {
		host, _ := os.Hostname()
		c.MachineName = host
	}
	if c.MachineID == "" {
		c.MachineID = c.MachineName
	}
	if c.ReportIntervalSec <= 0 {
		c.ReportIntervalSec = 60
	}
	if c.StateFile == "" {
		home, _ := os.UserHomeDir()
		c.StateFile = filepath.Join(home, ".agent-status", "claude-sessions.json")
	}
	if c.CodexSessionsDir == "" {
		home, _ := os.UserHomeDir()
		c.CodexSessionsDir = filepath.Join(home, ".codex", "sessions")
	}
	if c.ClaudeProjectsDir == "" {
		home, _ := os.UserHomeDir()
		c.ClaudeProjectsDir = filepath.Join(home, ".claude", "projects")
	}
	if c.UsageStateFile == "" {
		home, _ := os.UserHomeDir()
		c.UsageStateFile = filepath.Join(home, ".agent-status", "usage-cursors.json")
	}
	if c.UsageIntervalSec <= 0 {
		c.UsageIntervalSec = 60
	}
	if c.UsageDiscoverSec <= 0 {
		c.UsageDiscoverSec = 600
	}
	// CommandPollSec default 5; explicit 0 disables command execution.
	if c.CommandPollSec < 0 {
		c.CommandPollSec = 5
	} else if c.CommandPollSec == 0 && !commandPollExplicitlyZero(data) {
		c.CommandPollSec = 5
	}
	if c.CcSwitchBin == "" {
		c.CcSwitchBin = "cc-switch"
	}
	if c.CcSwitchDB == "" {
		home, _ := os.UserHomeDir()
		c.CcSwitchDB = filepath.Join(home, ".cc-switch", "cc-switch.db")
	}
	return &c, nil
}

// commandPollExplicitlyZero detects `"command_poll_sec": 0` in raw JSON.
func commandPollExplicitlyZero(data []byte) bool {
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(data, &raw); err != nil {
		return false
	}
	v, ok := raw["command_poll_sec"]
	if !ok {
		return false
	}
	var n int
	if err := json.Unmarshal(v, &n); err != nil {
		return false
	}
	return n == 0
}
