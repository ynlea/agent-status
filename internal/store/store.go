package store

import "github.com/ynlea/agent-status/pkg/apitypes"

// Store is the persistence boundary for server and mock.
type Store interface {
	ApplyReport(req apitypes.ReportRequest) (changed []apitypes.Session, wasOnline bool)
	ListMachines() []apitypes.Machine
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

	Close() error
}
