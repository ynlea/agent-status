package apitypes

import "time"

// Provider app / command type / status enums for remote cc-switch control.

const (
	ProviderAppCodex  = "codex"
	ProviderAppClaude = "claude"
	ProviderAppAll    = "all"

	CommandTypeSwitchProvider   = "switch_provider"
	CommandTypeUpdateProvider   = "update_provider"
	CommandTypeRefreshProviders  = "refresh_providers"
	CommandTypeCreateProvider    = "create_provider"
	CommandTypeDeleteProvider    = "delete_provider"
	CommandTypeDuplicateProvider = "duplicate_provider"

	CommandStatusQueued    = "queued"
	CommandStatusRunning   = "running"
	CommandStatusSucceeded = "succeeded"
	CommandStatusFailed    = "failed"
	CommandStatusTimedOut  = "timed_out"
	CommandStatusCancelled = "cancelled"
)

// ValidProviderApp returns true for supported remote apps.
func ValidProviderApp(app string) bool {
	switch app {
	case ProviderAppCodex, ProviderAppClaude:
		return true
	default:
		return false
	}
}

// ValidCommandType returns true for supported command types.
func ValidCommandType(t string) bool {
	switch t {
	case CommandTypeSwitchProvider, CommandTypeUpdateProvider, CommandTypeRefreshProviders,
		CommandTypeCreateProvider, CommandTypeDeleteProvider, CommandTypeDuplicateProvider:
		return true
	default:
		return false
	}
}

// CommandTerminal reports whether status is a terminal state.
func CommandTerminal(status string) bool {
	switch status {
	case CommandStatusSucceeded, CommandStatusFailed, CommandStatusTimedOut, CommandStatusCancelled:
		return true
	default:
		return false
	}
}

// ProviderInfo is a redacted provider row for snapshots / App UI.
// Never includes plaintext API keys.
type ProviderInfo struct {
	ID                 string `json:"id"`
	Name               string `json:"name"`
	BaseURL            string `json:"base_url,omitempty"`
	Model              string `json:"model,omitempty"`
	ModelAlias         string `json:"model_alias,omitempty"`
	AnthropicModel     string `json:"anthropic_model,omitempty"`
	DefaultHaikuModel  string `json:"default_haiku_model,omitempty"`
	DefaultSonnetModel string `json:"default_sonnet_model,omitempty"`
	DefaultOpusModel   string `json:"default_opus_model,omitempty"`
	Category           string `json:"category,omitempty"`
	HasAPIKey          bool   `json:"has_api_key"`
}

// ProviderAppSnapshot is the providers list for one app on one machine.
type ProviderAppSnapshot struct {
	App       string         `json:"app"`
	CurrentID string         `json:"current_id,omitempty"`
	Providers []ProviderInfo `json:"providers"`
}

// ProvidersReportRequest is Monitor → Server snapshot push.
type ProvidersReportRequest struct {
	MachineID         string                `json:"machine_id"`
	MachineName       string                `json:"machine_name,omitempty"`
	Platform          string                `json:"platform,omitempty"`
	ReportedAt        time.Time             `json:"reported_at"`
	Apps              []ProviderAppSnapshot `json:"apps"`
	CcSwitchAvailable bool                  `json:"cc_switch_available"`
	CcSwitchCLIReady  bool                  `json:"cc_switch_cli_ready"`
	CcSwitchBin       string                `json:"cc_switch_bin,omitempty"`
}

// ProvidersListResponse is App → Server snapshot read.
type ProvidersListResponse struct {
	MachineID         string                `json:"machine_id"`
	Apps              []ProviderAppSnapshot `json:"apps"`
	UpdatedAt         time.Time             `json:"updated_at,omitempty"`
	CcSwitchAvailable bool                  `json:"cc_switch_available"`
	CcSwitchCLIReady  bool                  `json:"cc_switch_cli_ready"`
	CcSwitchBin       string                `json:"cc_switch_bin,omitempty"`
}

// Ready reports whether remote provider ops can run on this machine.
func (r ProvidersListResponse) Ready() bool {
	return r.CcSwitchAvailable && r.CcSwitchCLIReady
}

// CommandPayload carries switch/update parameters.
type CommandPayload struct {
	ProviderID         string `json:"provider_id,omitempty"`
	Name               string `json:"name,omitempty"`
	BaseURL            string `json:"base_url,omitempty"`
	APIKey             string `json:"api_key,omitempty"`
	Model              string `json:"model,omitempty"`
	ModelAlias         string `json:"model_alias,omitempty"`
	AnthropicModel     string `json:"anthropic_model,omitempty"`
	DefaultHaikuModel  string `json:"default_haiku_model,omitempty"`
	DefaultSonnetModel string `json:"default_sonnet_model,omitempty"`
	DefaultOpusModel   string `json:"default_opus_model,omitempty"`
}

// MachineCommand is a queued remote action for one machine.
type MachineCommand struct {
	ID           string         `json:"id"`
	MachineID    string         `json:"machine_id"`
	App          string         `json:"app"`
	Type         string         `json:"type"`
	Payload      CommandPayload `json:"payload"`
	Status       string         `json:"status"`
	ErrorMessage string         `json:"error_message,omitempty"`
	CreatedAt    time.Time      `json:"created_at"`
	StartedAt    *time.Time     `json:"started_at,omitempty"`
	FinishedAt   *time.Time     `json:"finished_at,omitempty"`
	LeaseUntil   *time.Time     `json:"lease_until,omitempty"`
}

// EnqueueCommandRequest is App → Server create command.
type EnqueueCommandRequest struct {
	App     string         `json:"app"`
	Type    string         `json:"type"`
	Payload CommandPayload `json:"payload"`
}

// EnqueueCommandResponse is the create command reply.
type EnqueueCommandResponse struct {
	CommandID string `json:"command_id"`
	Status    string `json:"status"`
}

// CommandsPullRequest is Monitor → Server pull.
type CommandsPullRequest struct {
	MachineID string `json:"machine_id"`
	Limit     int    `json:"limit,omitempty"`
}

// CommandsPullResponse returns leased commands.
type CommandsPullResponse struct {
	Commands []MachineCommand `json:"commands"`
}

// CommandResultRequest is Monitor → Server result callback.
type CommandResultRequest struct {
	MachineID       string                  `json:"machine_id"`
	Status          string                  `json:"status"`
	ErrorMessage    string                  `json:"error_message,omitempty"`
	ProvidersReport *ProvidersReportRequest `json:"providers_report,omitempty"`
}
