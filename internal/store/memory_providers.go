package store

import (
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/ynlea/agent-status/pkg/apitypes"
)

func (m *Memory) ensureProviderMaps() {
	if m.providerSnaps == nil {
		m.providerSnaps = make(map[string]apitypes.ProviderAppSnapshot)
	}
	if m.providerSnapAt == nil {
		m.providerSnapAt = make(map[string]time.Time)
	}
	if m.commands == nil {
		m.commands = make(map[string]apitypes.MachineCommand)
	}
}

func providerSnapKey(machineID, app string) string {
	return machineID + "|" + app
}

func (m *Memory) ApplyProvidersReport(req apitypes.ProvidersReportRequest) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.ensureProviderMaps()
	if strings.TrimSpace(req.MachineID) == "" {
		return fmt.Errorf("machine_id required")
	}
	now := req.ReportedAt
	if now.IsZero() {
		now = time.Now().UTC()
	}
	if prev, ok := m.machines[req.MachineID]; ok {
		prev.Online = true
		prev.LastSeenAt = now
		m.machines[req.MachineID] = prev
	}
	for _, appSnap := range req.Apps {
		if !apitypes.ValidProviderApp(appSnap.App) {
			continue
		}
		if appSnap.Providers == nil {
			appSnap.Providers = []apitypes.ProviderInfo{}
		}
		key := providerSnapKey(req.MachineID, appSnap.App)
		m.providerSnaps[key] = appSnap
		m.providerSnapAt[key] = now
	}
	return nil
}

func (m *Memory) ListProviders(machineID, app string) (apitypes.ProvidersListResponse, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	out := apitypes.ProvidersListResponse{
		MachineID: machineID,
		Apps:      []apitypes.ProviderAppSnapshot{},
	}
	if machineID == "" {
		return out, fmt.Errorf("machine_id required")
	}
	app = strings.TrimSpace(app)
	var latest time.Time
	if app == "" || app == "all" {
		var keys []string
		for k := range m.providerSnaps {
			if strings.HasPrefix(k, machineID+"|") {
				keys = append(keys, k)
			}
		}
		sort.Strings(keys)
		for _, k := range keys {
			snap := m.providerSnaps[k]
			if snap.Providers == nil {
				snap.Providers = []apitypes.ProviderInfo{}
			}
			out.Apps = append(out.Apps, snap)
			if t := m.providerSnapAt[k]; t.After(latest) {
				latest = t
			}
		}
	} else {
		if !apitypes.ValidProviderApp(app) {
			return out, fmt.Errorf("app must be codex|claude|all")
		}
		key := providerSnapKey(machineID, app)
		if snap, ok := m.providerSnaps[key]; ok {
			if snap.Providers == nil {
				snap.Providers = []apitypes.ProviderInfo{}
			}
			out.Apps = append(out.Apps, snap)
			latest = m.providerSnapAt[key]
		}
	}
	out.UpdatedAt = latest
	return out, nil
}

func (m *Memory) EnqueueCommand(machineID string, req apitypes.EnqueueCommandRequest) (apitypes.MachineCommand, error) {
	if err := validateEnqueue(machineID, req); err != nil {
		return apitypes.MachineCommand{}, err
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	m.ensureProviderMaps()
	now := time.Now().UTC()
	cmd := apitypes.MachineCommand{
		ID:        newCommandID(),
		MachineID: machineID,
		App:       req.App,
		Type:      req.Type,
		Payload:   req.Payload,
		Status:    apitypes.CommandStatusQueued,
		CreatedAt: now,
	}
	m.commands[cmd.ID] = cmd
	return cmd, nil
}

func (m *Memory) PullCommands(machineID string, limit int) ([]apitypes.MachineCommand, error) {
	if strings.TrimSpace(machineID) == "" {
		return nil, fmt.Errorf("machine_id required")
	}
	// Serial queue: at most one leased/running command per machine.
	limit = 1
	m.mu.Lock()
	defer m.mu.Unlock()
	m.ensureProviderMaps()
	now := time.Now().UTC()
	m.expireCommandsLocked(now)

	for _, c := range m.commands {
		if c.MachineID == machineID && c.Status == apitypes.CommandStatusRunning {
			return []apitypes.MachineCommand{}, nil
		}
	}

	var queued []apitypes.MachineCommand
	for _, c := range m.commands {
		if c.MachineID == machineID && c.Status == apitypes.CommandStatusQueued {
			queued = append(queued, c)
		}
	}
	sort.Slice(queued, func(i, j int) bool {
		return queued[i].CreatedAt.Before(queued[j].CreatedAt)
	})
	if len(queued) > limit {
		queued = queued[:limit]
	}

	leaseUntil := now.Add(time.Duration(CommandLeaseSec) * time.Second)
	out := make([]apitypes.MachineCommand, 0, len(queued))
	for _, cmd := range queued {
		cmd.Status = apitypes.CommandStatusRunning
		st := now
		lu := leaseUntil
		cmd.StartedAt = &st
		cmd.LeaseUntil = &lu
		m.commands[cmd.ID] = cmd
		out = append(out, cmd)
	}
	return out, nil
}

func (m *Memory) CompleteCommand(id string, req apitypes.CommandResultRequest) (apitypes.MachineCommand, error) {
	status, err := sanitizeResultStatus(req.Status)
	if err != nil {
		return apitypes.MachineCommand{}, err
	}
	if strings.TrimSpace(id) == "" {
		return apitypes.MachineCommand{}, fmt.Errorf("command id required")
	}
	if strings.TrimSpace(req.MachineID) == "" {
		return apitypes.MachineCommand{}, fmt.Errorf("machine_id required")
	}

	m.mu.Lock()
	m.ensureProviderMaps()
	now := time.Now().UTC()
	m.expireCommandsLocked(now)
	cmd, ok := m.commands[id]
	if !ok {
		m.mu.Unlock()
		return apitypes.MachineCommand{}, fmt.Errorf("command not found")
	}
	if cmd.MachineID != req.MachineID {
		m.mu.Unlock()
		return apitypes.MachineCommand{}, fmt.Errorf("machine_id mismatch")
	}
	if apitypes.CommandTerminal(cmd.Status) {
		m.mu.Unlock()
		out := cmd
		out.Payload = stripAPIKey(out.Payload)
		return out, nil
	}
	errMsg := strings.TrimSpace(req.ErrorMessage)
	if len(errMsg) > 500 {
		errMsg = errMsg[:500]
	}
	cmd.Status = status
	cmd.ErrorMessage = errMsg
	cmd.Payload = stripAPIKey(cmd.Payload)
	ft := now
	cmd.FinishedAt = &ft
	cmd.LeaseUntil = nil
	m.commands[id] = cmd
	m.mu.Unlock()

	if req.ProvidersReport != nil {
		report := *req.ProvidersReport
		// Bind snapshot to the command's machine; never allow cross-machine overwrite.
		report.MachineID = req.MachineID
		_ = m.ApplyProvidersReport(report)
	}
	out := cmd
	out.Payload = stripAPIKey(out.Payload)
	return out, nil
}

func (m *Memory) GetCommand(id string) (apitypes.MachineCommand, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.ensureProviderMaps()
	m.expireCommandsLocked(time.Now().UTC())
	cmd, ok := m.commands[id]
	if !ok {
		return apitypes.MachineCommand{}, fmt.Errorf("command not found")
	}
	cmd.Payload = stripAPIKey(cmd.Payload)
	return cmd, nil
}

func (m *Memory) ExpireCommands(now time.Time) int {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.ensureProviderMaps()
	return m.expireCommandsLocked(now)
}

func (m *Memory) expireCommandsLocked(now time.Time) int {
	if now.IsZero() {
		now = time.Now().UTC()
	}
	n := 0
	queuedCut := now.Add(-time.Duration(CommandQueuedTimeoutSec) * time.Second)
	runningCut := now.Add(-time.Duration(CommandRunningTimeoutSec) * time.Second)
	for id, cmd := range m.commands {
		switch cmd.Status {
		case apitypes.CommandStatusQueued:
			if cmd.CreatedAt.Before(queuedCut) {
				cmd.Status = apitypes.CommandStatusTimedOut
				cmd.ErrorMessage = "queued timeout"
				ft := now
				cmd.FinishedAt = &ft
				cmd.Payload = stripAPIKey(cmd.Payload)
				m.commands[id] = cmd
				n++
			}
		case apitypes.CommandStatusRunning:
			timeout := false
			if cmd.StartedAt != nil && cmd.StartedAt.Before(runningCut) {
				timeout = true
			}
			if cmd.LeaseUntil != nil && cmd.LeaseUntil.Before(now) {
				timeout = true
			}
			if timeout {
				cmd.Status = apitypes.CommandStatusTimedOut
				cmd.ErrorMessage = "running timeout"
				ft := now
				cmd.FinishedAt = &ft
				cmd.LeaseUntil = nil
				cmd.Payload = stripAPIKey(cmd.Payload)
				m.commands[id] = cmd
				n++
			}
		}
	}
	return n
}
