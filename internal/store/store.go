package store

import (
	"time"

	"github.com/ynlea/agent-status/pkg/apitypes"
)

// Store is the persistence boundary for server and mock.
type Store interface {
	ApplyReport(req apitypes.ReportRequest) (changed []apitypes.Session, wasOnline bool)
	ListMachines() []apitypes.Machine
	// RenameMachine sets a user-facing machine name and locks it against monitor overwrites.
	RenameMachine(machineID, name string) (apitypes.Machine, error)
	ListSessions(machineID string) []apitypes.Session
	ListHistory(limit int) []apitypes.HistoryEntry
	// Cleanup removes history older than maxAge and trims to maxCount; marks stale machines offline.
	Cleanup(maxAgeSeconds int64, maxCount int, machineOfflineAfter int64) (historyDeleted int, machinesOffline int)

	// ApplyUsageReport upserts usage events by global dedupe key. Touches machine last_seen when possible.
	ApplyUsageReport(req apitypes.UsageReportRequest) (accepted, duplicates int)
	// UsageSummary aggregates metrics for the query window.
	UsageSummary(q apitypes.UsageQuery) apitypes.UsageSummaryResponse
	// UsageBreakdown aggregates metrics grouped by agent|model|machine|day.
	UsageBreakdown(q apitypes.UsageQuery) apitypes.UsageBreakdownResponse

	// LookupModelPrice resolves unit prices for cost estimation.
	LookupModelPrice(model string) (ModelPrice, bool)
	// UpsertModelPrice inserts/updates a price row subject to source priority (override wins).
	UpsertModelPrice(p ModelPrice, source string) error
	// ListModelPrices returns a snapshot of known prices.
	ListModelPrices() []ModelPrice

	// ApplyProvidersReport replaces provider snapshots for the machine (per app).
	ApplyProvidersReport(req apitypes.ProvidersReportRequest) error
	// ListProviders returns cached snapshots; app empty or "all" returns every app.
	ListProviders(machineID, app string) (apitypes.ProvidersListResponse, error)

	// EnqueueCommand queues a remote command for a machine (FIFO).
	EnqueueCommand(machineID string, req apitypes.EnqueueCommandRequest) (apitypes.MachineCommand, error)
	// PullCommands leases up to limit queued commands (serial: at most one running per machine).
	PullCommands(machineID string, limit int) ([]apitypes.MachineCommand, error)
	// CompleteCommand records monitor result and strips api_key from stored payload.
	CompleteCommand(id string, req apitypes.CommandResultRequest) (apitypes.MachineCommand, error)
	// GetCommand returns a command by id.
	GetCommand(id string) (apitypes.MachineCommand, error)
	// ExpireCommands marks timed-out queued/running commands; returns how many flipped.
	ExpireCommands(now time.Time) int

	Close() error
}
