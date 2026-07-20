package store

import (
	"sync"
	"time"

	"github.com/ynlea/agent-status/pkg/apitypes"
)

type sessionKey struct {
	MachineID string
	Agent     string
	SessionID string
}

// Memory is an in-memory store for the contract mock server.
type Memory struct {
	mu       sync.RWMutex
	machines map[string]apitypes.Machine
	sessions map[sessionKey]apitypes.Session
	history  []apitypes.HistoryEntry
	usage    map[string]apitypes.UsageEvent // dedupe_key -> event
	maxHist  int
	prices   *priceCache
}

func NewMemory(maxHistory int) *Memory {
	if maxHistory <= 0 {
		maxHistory = 50
	}
	m := &Memory{
		machines: make(map[string]apitypes.Machine),
		sessions: make(map[sessionKey]apitypes.Session),
		history:  make([]apitypes.HistoryEntry, 0, maxHistory),
		usage:    make(map[string]apitypes.UsageEvent),
		maxHist:  maxHistory,
		prices:   newPriceCache(),
	}
	for _, p := range bundledPublicPrices {
		m.prices.upsert(p, SourceBundled)
	}
	for _, p := range overridePublicPrices {
		m.prices.upsert(p, SourceOverride)
	}
	return m
}

func (m *Memory) LookupModelPrice(model string) (ModelPrice, bool) {
	return m.prices.lookup(model)
}

func (m *Memory) UpsertModelPrice(p ModelPrice, source string) error {
	m.prices.upsert(p, source)
	return nil
}

func (m *Memory) ListModelPrices() []ModelPrice {
	return m.prices.snapshot()
}

func (m *Memory) Close() error { return nil }

// ApplyReport merges a report and returns sessions that changed state (for notify).
func (m *Memory) ApplyReport(req apitypes.ReportRequest) (changed []apitypes.Session, wasOnline bool) {
	m.mu.Lock()
	defer m.mu.Unlock()

	now := req.ReportedAt
	if now.IsZero() {
		now = time.Now().UTC()
	}

	prev, ok := m.machines[req.MachineID]
	wasOnline = ok && prev.Online

	ver := req.Version
	if ver == "" && ok {
		ver = prev.Version
	}
	m.machines[req.MachineID] = apitypes.Machine{
		MachineID:   req.MachineID,
		MachineName: req.MachineName,
		Platform:    req.Platform,
		Version:     ver,
		Online:      true,
		LastSeenAt:  now,
	}

	keep := make(map[sessionKey]struct{}, len(req.Sessions))
	for _, s := range req.Sessions {
		if s.SessionID == "" || s.Agent == "" {
			continue
		}
		if !s.State.Valid() {
			continue
		}
		s.MachineID = req.MachineID
		if s.MachineName == "" {
			s.MachineName = req.MachineName
		}
		if s.UpdatedAt.IsZero() {
			s.UpdatedAt = now
		}
		key := sessionKey{req.MachineID, s.Agent, s.SessionID}
		keep[key] = struct{}{}
		old, exists := m.sessions[key]
		if !exists || old.State != s.State {
			from := apitypes.SessionState("")
			if exists {
				from = old.State
			}
			m.appendHistoryLocked(apitypes.HistoryEntry{
				MachineID:   s.MachineID,
				MachineName: s.MachineName,
				Agent:       s.Agent,
				SessionID:   s.SessionID,
				DisplayName: s.DisplayName,
				FromState:   from,
				ToState:     s.State,
				Message:     s.Message,
				At:          s.UpdatedAt,
			})
			changed = append(changed, s)
		}
		m.sessions[key] = s
	}
	// Drop sessions for this machine that were not in the snapshot.
	for key, old := range m.sessions {
		if key.MachineID != req.MachineID {
			continue
		}
		if _, ok := keep[key]; ok {
			continue
		}
		if old.State != apitypes.StateIdle {
			gone := old
			gone.State = apitypes.StateIdle
			gone.UpdatedAt = now
			m.appendHistoryLocked(apitypes.HistoryEntry{
				MachineID:   old.MachineID,
				MachineName: old.MachineName,
				Agent:       old.Agent,
				SessionID:   old.SessionID,
				DisplayName: old.DisplayName,
				FromState:   old.State,
				ToState:     apitypes.StateIdle,
				Message:     old.Message,
				At:          now,
			})
			changed = append(changed, gone)
		}
		delete(m.sessions, key)
	}
	return changed, wasOnline
}

func (m *Memory) appendHistoryLocked(e apitypes.HistoryEntry) {
	m.history = append(m.history, e)
	if len(m.history) > m.maxHist {
		m.history = m.history[len(m.history)-m.maxHist:]
	}
}

func (m *Memory) ListMachines() []apitypes.Machine {
	m.mu.RLock()
	defer m.mu.RUnlock()
	out := make([]apitypes.Machine, 0, len(m.machines))
	for _, v := range m.machines {
		out = append(out, v)
	}
	return out
}

func (m *Memory) ListSessions(machineID string) []apitypes.Session {
	m.mu.RLock()
	defer m.mu.RUnlock()
	out := make([]apitypes.Session, 0)
	for k, s := range m.sessions {
		if machineID == "" || k.MachineID == machineID {
			out = append(out, s)
		}
	}
	return out
}

func (m *Memory) ListHistory(limit int) []apitypes.HistoryEntry {
	m.mu.RLock()
	defer m.mu.RUnlock()
	if limit <= 0 || limit > len(m.history) {
		limit = len(m.history)
	}
	start := len(m.history) - limit
	out := make([]apitypes.HistoryEntry, limit)
	copy(out, m.history[start:])
	for i, j := 0, len(out)-1; i < j; i, j = i+1, j-1 {
		out[i], out[j] = out[j], out[i]
	}
	return out
}

func (m *Memory) ApplyUsageReport(req apitypes.UsageReportRequest) (accepted, duplicates int) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if req.MachineID == "" {
		return 0, 0
	}
	now := req.ReportedAt
	if now.IsZero() {
		now = time.Now().UTC()
	}
	prev, ok := m.machines[req.MachineID]
	name := req.MachineName
	if name == "" && ok {
		name = prev.MachineName
	}
	platform := req.Platform
	if platform == "" && ok {
		platform = prev.Platform
	}
	m.machines[req.MachineID] = apitypes.Machine{
		MachineID:   req.MachineID,
		MachineName: name,
		Platform:    platform,
		Online:      true,
		LastSeenAt:  now,
	}
		for _, raw := range req.Events {
			e, ok := sanitizeUsageEvent(req.MachineID, raw)
			if !ok {
				continue
			}
			if old, exists := m.usage[e.DedupeKey]; exists {
				if isUnknownUsageModel(old.Model) && !isUnknownUsageModel(e.Model) {
					old.Model = e.Model
					m.usage[e.DedupeKey] = old
					accepted++
					continue
				}
				duplicates++
				continue
			}
			m.usage[e.DedupeKey] = e
			accepted++
		}
	return accepted, duplicates
}

func (m *Memory) UsageSummary(q apitypes.UsageQuery) apitypes.UsageSummaryResponse {
	m.mu.RLock()
	defer m.mu.RUnlock()
	byModel := map[string]apitypes.UsageMetrics{}
	for _, e := range m.usage {
		if !eventMatches(e, q) {
			continue
		}
		addEventToModelMap(byModel, e)
	}
	return finalizeSummaryFromModelMap(m.LookupModelPrice, q, byModel)
}

func (m *Memory) UsageBreakdown(q apitypes.UsageQuery) apitypes.UsageBreakdownResponse {
	m.mu.RLock()
	defer m.mu.RUnlock()
	groupBy := validateGroupBy(q.GroupBy)
	groups := map[string]map[string]apitypes.UsageMetrics{}
	for _, e := range m.usage {
		if !eventMatches(e, q) {
			continue
		}
		gk := groupKey(e, groupBy)
		if groups[gk] == nil {
			groups[gk] = map[string]apitypes.UsageMetrics{}
		}
		addEventToModelMap(groups[gk], e)
	}
	return finalizeBreakdown(m.LookupModelPrice, q, groupBy, groups)
}

func (m *Memory) Cleanup(maxAgeSeconds int64, maxCount int, machineOfflineAfter int64) (historyDeleted int, machinesOffline int) {
	m.mu.Lock()
	defer m.mu.Unlock()
	now := time.Now().UTC()
	if maxAgeSeconds > 0 {
		cut := now.Add(-time.Duration(maxAgeSeconds) * time.Second)
		kept := m.history[:0]
		for _, h := range m.history {
			if h.At.Before(cut) {
				historyDeleted++
				continue
			}
			kept = append(kept, h)
		}
		m.history = kept
	}
	if maxCount > 0 && len(m.history) > maxCount {
		extra := len(m.history) - maxCount
		historyDeleted += extra
		m.history = m.history[extra:]
	}
	if machineOfflineAfter > 0 {
		cut := now.Add(-time.Duration(machineOfflineAfter) * time.Second)
		for id, mac := range m.machines {
			if mac.Online && mac.LastSeenAt.Before(cut) {
				mac.Online = false
				m.machines[id] = mac
				machinesOffline++
			}
		}
	}
	return historyDeleted, machinesOffline
}
