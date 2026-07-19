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
