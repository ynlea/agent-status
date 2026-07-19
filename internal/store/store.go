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
	Close() error
}
