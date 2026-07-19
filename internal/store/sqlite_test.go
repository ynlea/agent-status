package store

import (
	"path/filepath"
	"testing"
	"time"

	"github.com/ynlea/agent-status/pkg/apitypes"
)

func TestSQLiteTwoMachinesAndCleanup(t *testing.T) {
	path := filepath.Join(t.TempDir(), "t.db")
	s, err := NewSQLite(path)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()

	now := time.Now().UTC()
	_, _ = s.ApplyReport(apitypes.ReportRequest{
		MachineID: "m1", MachineName: "a", Platform: "linux", ReportedAt: now,
		Sessions: []apitypes.Session{
			{Agent: "claude", SessionID: "s1", DisplayName: "one", State: apitypes.StateWorking, UpdatedAt: now},
			{Agent: "codex", SessionID: "s2", DisplayName: "two", State: apitypes.StateConfirm, UpdatedAt: now},
		},
	})
	_, _ = s.ApplyReport(apitypes.ReportRequest{
		MachineID: "m2", MachineName: "b", Platform: "windows", ReportedAt: now,
		Sessions: []apitypes.Session{
			{Agent: "claude", SessionID: "s9", DisplayName: "win", State: apitypes.StateDone, UpdatedAt: now},
		},
	})

	if len(s.ListMachines()) != 2 {
		t.Fatalf("machines=%d", len(s.ListMachines()))
	}
	if len(s.ListSessions("m1")) != 2 {
		t.Fatalf("m1 sessions=%d", len(s.ListSessions("m1")))
	}

	// force old history then cleanup
	_, err = s.db.Exec(`UPDATE history SET at = ?`, time.Now().UTC().Add(-48*time.Hour).Format(time.RFC3339Nano))
	if err != nil {
		t.Fatal(err)
	}
	del, _ := s.Cleanup(3600, 50, 1)
	if del == 0 {
		t.Fatal("expected history deleted by TTL")
	}
}

func TestSQLiteReportDropsMissingSessions(t *testing.T) {
	path := filepath.Join(t.TempDir(), "drop.db")
	s, err := NewSQLite(path)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	now := time.Now().UTC()
	_, _ = s.ApplyReport(apitypes.ReportRequest{
		MachineID: "m1", MachineName: "a", Platform: "linux", ReportedAt: now,
		Sessions: []apitypes.Session{
			{Agent: "claude", SessionID: "keep", DisplayName: "k", State: apitypes.StateWorking, UpdatedAt: now},
			{Agent: "claude", SessionID: "test-sum", DisplayName: "x", State: apitypes.StateWorking, Message: "编译一份release的apk", UpdatedAt: now},
		},
	})
	if len(s.ListSessions("m1")) != 2 {
		t.Fatalf("want 2 sessions, got %d", len(s.ListSessions("m1")))
	}
	_, _ = s.ApplyReport(apitypes.ReportRequest{
		MachineID: "m1", MachineName: "a", Platform: "linux", ReportedAt: now.Add(time.Second),
		Sessions: []apitypes.Session{
			{Agent: "claude", SessionID: "keep", DisplayName: "k", State: apitypes.StateDone, UpdatedAt: now.Add(time.Second)},
		},
	})
	list := s.ListSessions("m1")
	if len(list) != 1 {
		t.Fatalf("want 1 session after drop, got %d", len(list))
	}
	if list[0].SessionID != "keep" {
		t.Fatalf("unexpected session %s", list[0].SessionID)
	}
}
