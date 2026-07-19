package monitor

import (
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
	// CodexAppServer enables the codex app-server JSON-RPC channel (default true).
	// File rollout scan remains the fallback/merge source.
	CodexAppServer *bool `json:"codex_app_server,omitempty"`
	// CodexFileWatch enables real-time watching of ordinary Codex rollout files (default true).
	// A periodic full scan remains enabled to recover from missed filesystem events.
	CodexFileWatch *bool `json:"codex_file_watch,omitempty"`
	// CodexSandboxMode is passed to app-server as -c sandbox_mode="...".
	// Empty means omit (Codex default). Examples: danger-full-access, workspace-write, read-only.
	// Do not hardcode a dangerous mode in code; set per machine via config when needed.
	CodexSandboxMode string `json:"codex_sandbox_mode,omitempty"`
}

func (c *Config) AppServerEnabled() bool {
	if c.CodexAppServer == nil {
		return true
	}
	return *c.CodexAppServer
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
		c.ReportIntervalSec = 15
	}
	if c.StateFile == "" {
		home, _ := os.UserHomeDir()
		c.StateFile = filepath.Join(home, ".agent-status", "claude-sessions.json")
	}
	if c.CodexSessionsDir == "" {
		home, _ := os.UserHomeDir()
		c.CodexSessionsDir = filepath.Join(home, ".codex", "sessions")
	}
	return &c, nil
}
