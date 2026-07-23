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

func TestSQLiteStartedAtStableAndRealUsage(t *testing.T) {
	path := filepath.Join(t.TempDir(), "metrics.db")
	s, err := NewSQLite(path)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()

	t0 := time.Date(2026, 7, 21, 10, 0, 0, 0, time.UTC)
	t1 := t0.Add(5 * time.Minute)
	_, _ = s.ApplyReport(apitypes.ReportRequest{
		MachineID: "m1", MachineName: "host-raw", Platform: "linux", ReportedAt: t0,
		Sessions: []apitypes.Session{
			{Agent: "claude", SessionID: "s1", DisplayName: "demo", State: apitypes.StateWorking, UpdatedAt: t0},
		},
	})
	list := s.ListSessions("m1")
	if len(list) != 1 || list[0].StartedAt == nil {
		t.Fatalf("expected started_at, got %+v", list)
	}
	first := *list[0].StartedAt

	_, _ = s.ApplyReport(apitypes.ReportRequest{
		MachineID: "m1", MachineName: "host-raw", Platform: "linux", ReportedAt: t1,
		Sessions: []apitypes.Session{
			{Agent: "claude", SessionID: "s1", DisplayName: "demo", State: apitypes.StateWorking, Message: "still", UpdatedAt: t1},
		},
	})
	list = s.ListSessions("m1")
	if list[0].StartedAt == nil || !list[0].StartedAt.Equal(first) {
		t.Fatalf("started_at changed: first=%v now=%v", first, list[0].StartedAt)
	}

	acc, _ := s.ApplyUsageReport(apitypes.UsageReportRequest{
		MachineID: "m1", MachineName: "host-raw", Platform: "linux", ReportedAt: t1,
		Events: []apitypes.UsageEvent{
			{
				DedupeKey: "d1", Agent: "claude", Model: "opus", SessionID: "s1",
				OccurredAt: t1, InputTokens: 100, OutputTokens: 50, ReasoningTokens: 10,
				CacheWriteTokens: 20, CacheHitTokens: 5,
			},
			{
				DedupeKey: "d2", Agent: "claude", Model: "opus", SessionID: "s1",
				OccurredAt: t1, InputTokens: 15, OutputTokens: 0,
			},
		},
	})
	if acc != 2 {
		t.Fatalf("accepted=%d", acc)
	}
	list = s.ListSessions("m1")
	// 100+50+10+20+5 + 15 = 200
	if list[0].RealUsage != 200 {
		t.Fatalf("real_usage=%d want 200", list[0].RealUsage)
	}
}

func TestSQLiteRenameThenReportUsesLockedName(t *testing.T) {
	path := filepath.Join(t.TempDir(), "rename.db")
	s, err := NewSQLite(path)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	now := time.Now().UTC()
	_, _ = s.ApplyReport(apitypes.ReportRequest{
		MachineID: "m1", MachineName: "raw-hostname", Platform: "linux", ReportedAt: now,
		Sessions: []apitypes.Session{
			{Agent: "claude", SessionID: "s1", DisplayName: "demo", State: apitypes.StateWorking, UpdatedAt: now},
		},
	})
	if _, err := s.RenameMachine("m1", "书房电脑"); err != nil {
		t.Fatal(err)
	}
	changed, _ := s.ApplyReport(apitypes.ReportRequest{
		MachineID: "m1", MachineName: "raw-hostname", Platform: "linux", ReportedAt: now.Add(time.Second),
		Sessions: []apitypes.Session{
			{Agent: "claude", SessionID: "s1", DisplayName: "demo", State: apitypes.StateConfirm, UpdatedAt: now.Add(time.Second)},
		},
	})
	if len(changed) != 1 {
		t.Fatalf("changed=%d", len(changed))
	}
	if changed[0].MachineName != "书房电脑" {
		t.Fatalf("changed machine_name=%q", changed[0].MachineName)
	}
	list := s.ListSessions("m1")
	if len(list) != 1 || list[0].MachineName != "书房电脑" {
		t.Fatalf("list machine_name=%v", list)
	}
	hist := s.ListHistory(5)
	if len(hist) == 0 || hist[0].MachineName != "书房电脑" {
		t.Fatalf("history machine_name=%v", hist)
	}
}

func TestSQLiteParentSessionID(t *testing.T) {
	path := filepath.Join(t.TempDir(), "parent.db")
	s, err := NewSQLite(path)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()

	now := time.Now().UTC()
	_, _ = s.ApplyReport(apitypes.ReportRequest{
		MachineID: "m1", MachineName: "a", Platform: "linux", ReportedAt: now,
		Sessions: []apitypes.Session{
			{Agent: "codex", SessionID: "root", DisplayName: "main", State: apitypes.StateWorking, UpdatedAt: now},
			{Agent: "codex", SessionID: "child", DisplayName: "Raman", State: apitypes.StateWorking, ParentSessionID: "root", UpdatedAt: now},
		},
	})
	list := s.ListSessions("m1")
	if len(list) != 2 {
		t.Fatalf("len=%d", len(list))
	}
	byID := map[string]apitypes.Session{}
	for _, sess := range list {
		byID[sess.SessionID] = sess
	}
	if byID["root"].ParentSessionID != "" {
		t.Fatalf("root parent=%q", byID["root"].ParentSessionID)
	}
	if byID["child"].ParentSessionID != "root" {
		t.Fatalf("child parent=%q", byID["child"].ParentSessionID)
	}
}
