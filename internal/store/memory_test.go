package store

import (
	"testing"
	"time"

	"github.com/ynlea/agent-status/pkg/apitypes"
)

func TestApplyReportStateChange(t *testing.T) {
	m := NewMemory(10)
	now := time.Date(2026, 7, 18, 12, 0, 0, 0, time.UTC)
	req := apitypes.ReportRequest{
		MachineID:   "m1",
		MachineName: "desk",
		Platform:    "linux",
		ReportedAt:  now,
		Sessions: []apitypes.Session{{
			Agent:       "claude",
			SessionID:   "s1",
			DisplayName: "demo",
			State:       apitypes.StateConfirm,
			UpdatedAt:   now,
		}},
	}
	changed, wasOnline := m.ApplyReport(req)
	if wasOnline {
		t.Fatal("expected first report not previously online")
	}
	if len(changed) != 1 {
		t.Fatalf("changed=%d", len(changed))
	}
	machines := m.ListMachines()
	if len(machines) != 1 || machines[0].MachineID != "m1" {
		t.Fatalf("machines=%v", machines)
	}
	sessions := m.ListSessions("m1")
	if len(sessions) != 1 || sessions[0].State != apitypes.StateConfirm {
		t.Fatalf("sessions=%v", sessions)
	}
	// same state: no change
	changed, _ = m.ApplyReport(req)
	if len(changed) != 0 {
		t.Fatalf("expected no change, got %d", len(changed))
	}
	// state flip
	req.Sessions[0].State = apitypes.StateWorking
	changed, _ = m.ApplyReport(req)
	if len(changed) != 1 {
		t.Fatalf("expected 1 change, got %d", len(changed))
	}
	hist := m.ListHistory(10)
	if len(hist) < 2 {
		t.Fatalf("history len=%d", len(hist))
	}
}

func TestMemoryStartedAtRealUsageAndRename(t *testing.T) {
	m := NewMemory(20)
	t0 := time.Date(2026, 7, 21, 11, 0, 0, 0, time.UTC)
	t1 := t0.Add(2 * time.Minute)
	changed, _ := m.ApplyReport(apitypes.ReportRequest{
		MachineID: "m1", MachineName: "raw", Platform: "linux", ReportedAt: t0,
		Sessions: []apitypes.Session{
			{Agent: "claude", SessionID: "s1", DisplayName: "demo", State: apitypes.StateWorking, UpdatedAt: t0},
		},
	})
	if len(changed) != 1 || changed[0].StartedAt == nil {
		t.Fatalf("changed=%+v", changed)
	}
	first := *changed[0].StartedAt
	_, _ = m.ApplyReport(apitypes.ReportRequest{
		MachineID: "m1", MachineName: "raw", Platform: "linux", ReportedAt: t1,
		Sessions: []apitypes.Session{
			{Agent: "claude", SessionID: "s1", DisplayName: "demo", State: apitypes.StateWorking, Message: "x", UpdatedAt: t1},
		},
	})
	list := m.ListSessions("m1")
	if list[0].StartedAt == nil || !list[0].StartedAt.Equal(first) {
		t.Fatalf("started_at not stable: %v vs %v", first, list[0].StartedAt)
	}

	m.ApplyUsageReport(apitypes.UsageReportRequest{
		MachineID: "m1", MachineName: "raw", Platform: "linux", ReportedAt: t1,
		Events: []apitypes.UsageEvent{
			{DedupeKey: "u1", Agent: "claude", Model: "m", SessionID: "s1", OccurredAt: t1, InputTokens: 40, OutputTokens: 10},
		},
	})
	list = m.ListSessions("m1")
	if list[0].RealUsage != 50 {
		t.Fatalf("real_usage=%d", list[0].RealUsage)
	}

	if _, err := m.RenameMachine("m1", "客厅 Mac"); err != nil {
		t.Fatal(err)
	}
	changed, _ = m.ApplyReport(apitypes.ReportRequest{
		MachineID: "m1", MachineName: "raw", Platform: "linux", ReportedAt: t1.Add(time.Second),
		Sessions: []apitypes.Session{
			{Agent: "claude", SessionID: "s1", DisplayName: "demo", State: apitypes.StateDone, UpdatedAt: t1.Add(time.Second)},
		},
	})
	if len(changed) != 1 || changed[0].MachineName != "客厅 Mac" {
		t.Fatalf("rename notify name=%+v", changed)
	}
}
