package store

import (
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/ynlea/agent-status/pkg/apitypes"
)

func TestUsageIdempotentAndSummary(t *testing.T) {
	path := filepath.Join(t.TempDir(), "usage.db")
	s, err := NewSQLite(path)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()

	now := time.Date(2026, 7, 19, 12, 0, 0, 0, time.UTC)
	req := apitypes.UsageReportRequest{
		MachineID: "m1", MachineName: "desk", Platform: "linux", ReportedAt: now,
		Events: []apitypes.UsageEvent{
			{
				DedupeKey: "claude:msg1", Agent: "claude", Model: "claude-sonnet-4-5",
				OccurredAt: now, InputTokens: 100, OutputTokens: 50, CacheHitTokens: 1000,
			},
			{
				DedupeKey: "codex:e1", Agent: "codex", Model: "gpt-5.2",
				OccurredAt: now.Add(time.Minute), InputTokens: 200, OutputTokens: 20, ReasoningTokens: 10, CacheHitTokens: 500,
			},
		},
	}
	acc, dup := s.ApplyUsageReport(req)
	if acc != 2 || dup != 0 {
		t.Fatalf("first report acc=%d dup=%d", acc, dup)
	}
	acc, dup = s.ApplyUsageReport(req)
	if acc != 0 || dup != 2 {
		t.Fatalf("second report acc=%d dup=%d", acc, dup)
	}

	sum := s.UsageSummary(apitypes.UsageQuery{
		From: now.Add(-time.Hour), To: now.Add(time.Hour),
	})
	if sum.InputTokens != 300 || sum.OutputTokens != 70 || sum.ReasoningTokens != 10 || sum.CacheHitTokens != 1500 {
		t.Fatalf("metrics=%+v", sum.UsageMetrics)
	}
	// real = in + out+reason + cache_write + cache_hit = 300 + 80 + 0 + 1500
	if sum.RealUsage != 1880 {
		t.Fatalf("real_usage=%d", sum.RealUsage)
	}
	if sum.CacheHitRate == nil || *sum.CacheHitRate <= 0 {
		t.Fatalf("hit rate=%v", sum.CacheHitRate)
	}
	if sum.EstimatedCostUSD == nil {
		t.Fatal("expected estimated cost")
	}

	bd := s.UsageBreakdown(apitypes.UsageQuery{
		From: now.Add(-time.Hour), To: now.Add(time.Hour), GroupBy: "agent",
	})
	if len(bd.Groups) != 2 {
		t.Fatalf("groups=%v", bd.Groups)
	}

	// machine isolation
	_, _ = s.ApplyUsageReport(apitypes.UsageReportRequest{
		MachineID: "m2", MachineName: "other", Platform: "linux", ReportedAt: now,
		Events: []apitypes.UsageEvent{{
			DedupeKey: "claude:other", Agent: "claude", Model: "claude-sonnet-4-5",
			OccurredAt: now, InputTokens: 999, OutputTokens: 1,
		}},
	})
	sumM1 := s.UsageSummary(apitypes.UsageQuery{
		From: now.Add(-time.Hour), To: now.Add(time.Hour), MachineID: "m1",
	})
	if sumM1.InputTokens != 300 {
		t.Fatalf("m1 input=%d", sumM1.InputTokens)
	}
}

func TestUsageBreakdownByProject(t *testing.T) {
	path := filepath.Join(t.TempDir(), "usage-project.db")
	s, err := NewSQLite(path)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()

	now := time.Date(2026, 7, 21, 10, 0, 0, 0, time.UTC)
	// Seed machine + session with cwd so project key can resolve path.
	_, _ = s.ApplyReport(apitypes.ReportRequest{
		MachineID: "m1", MachineName: "desk", Platform: "linux", ReportedAt: now,
		Sessions: []apitypes.Session{{
			MachineID: "m1", Agent: "claude", SessionID: "s-proj",
			DisplayName: "agent-status", State: apitypes.StateWorking,
			Cwd: "/home/u/projects/agent-status", UpdatedAt: now,
		}},
	})
	acc, _ := s.ApplyUsageReport(apitypes.UsageReportRequest{
		MachineID: "m1", MachineName: "desk", Platform: "linux", ReportedAt: now,
		Events: []apitypes.UsageEvent{{
			DedupeKey: "claude:p1", Agent: "claude", Model: "claude-sonnet-4-5",
			SessionID: "s-proj", OccurredAt: now, InputTokens: 100, OutputTokens: 20,
		}},
	})
	if acc != 1 {
		t.Fatalf("acc=%d", acc)
	}
	bd := s.UsageBreakdown(apitypes.UsageQuery{
		From: now.Add(-time.Hour), To: now.Add(time.Hour), GroupBy: "project",
	})
	if len(bd.Groups) != 1 {
		t.Fatalf("groups=%+v", bd.Groups)
	}
	wantKey := "desk" + "\x1f" + "/home/u/projects/agent-status"
	if bd.Groups[0].Key != wantKey {
		t.Fatalf("key=%q want=%q", bd.Groups[0].Key, wantKey)
	}
	if bd.Groups[0].RealUsage != 120 {
		t.Fatalf("real=%d", bd.Groups[0].RealUsage)
	}

	// Prune live session row; durable map should still resolve path.
	_, _ = s.ApplyReport(apitypes.ReportRequest{
		MachineID: "m1", MachineName: "desk", Platform: "linux", ReportedAt: now.Add(time.Minute),
		Sessions: []apitypes.Session{},
	})
	bd2 := s.UsageBreakdown(apitypes.UsageQuery{
		From: now.Add(-time.Hour), To: now.Add(time.Hour), GroupBy: "project",
	})
	if len(bd2.Groups) != 1 || bd2.Groups[0].Key != wantKey {
		t.Fatalf("after prune groups=%+v", bd2.Groups)
	}

	// Unknown path collapses to 未知项目 (not raw session id).
	acc2, _ := s.ApplyUsageReport(apitypes.UsageReportRequest{
		MachineID: "m1", MachineName: "desk", Platform: "linux", ReportedAt: now,
		Events: []apitypes.UsageEvent{{
			DedupeKey: "claude:orphan", Agent: "claude", Model: "claude-sonnet-4-5",
			SessionID: "orphan-session-id-xxx", OccurredAt: now, InputTokens: 10, OutputTokens: 1,
		}},
	})
	if acc2 != 1 {
		t.Fatalf("acc2=%d", acc2)
	}
	bd3 := s.UsageBreakdown(apitypes.UsageQuery{
		From: now.Add(-time.Hour), To: now.Add(time.Hour), GroupBy: "project",
	})
	var sawUnknown bool
	for _, g := range bd3.Groups {
		if g.Key == "desk"+"\x1f"+"未知项目" {
			sawUnknown = true
		}
		if strings.Contains(g.Key, "orphan-session") {
			t.Fatalf("should not expose raw session id: %q", g.Key)
		}
	}
	if !sawUnknown {
		t.Fatalf("expected 未知项目 group, got %+v", bd3.Groups)
	}
}

func TestUsageHitRateZeroDenom(t *testing.T) {
	m := NewMemory(10)
	// empty
	sum := m.UsageSummary(apitypes.UsageQuery{})
	if sum.CacheHitRate != nil {
		t.Fatalf("want nil rate, got %v", *sum.CacheHitRate)
	}
}

func TestLookupModelPriceGrokFallback(t *testing.T) {
	_, ok := LookupModelPrice("grok-4.5-build-free")
	if ok {
		t.Fatal("unexpected price for grok free alias")
	}
	_, ok = LookupModelPrice("claude-sonnet-4-5-20250929")
	if !ok {
		t.Fatal("expected sonnet price match")
	}
}

func TestWorkingStartedAtResets(t *testing.T) {
	path := filepath.Join(t.TempDir(), "started.db")
	s, err := NewSQLite(path)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	t1 := time.Date(2026, 7, 21, 10, 0, 0, 0, time.UTC)
	t2 := t1.Add(30 * time.Minute)
	t3 := t2.Add(10 * time.Minute)
	_, _ = s.ApplyReport(apitypes.ReportRequest{
		MachineID: "m1", MachineName: "desk", Platform: "linux", ReportedAt: t1,
		Sessions: []apitypes.Session{{
			MachineID: "m1", Agent: "claude", SessionID: "s1", DisplayName: "p",
			State: apitypes.StateWorking, UpdatedAt: t1,
		}},
	})
	list := s.ListSessions("m1")
	if len(list) != 1 || list[0].StartedAt == nil || !list[0].StartedAt.Equal(t1) {
		t.Fatalf("first working started=%v", list[0].StartedAt)
	}
	// still working later — started_at stable
	_, _ = s.ApplyReport(apitypes.ReportRequest{
		MachineID: "m1", MachineName: "desk", Platform: "linux", ReportedAt: t2,
		Sessions: []apitypes.Session{{
			MachineID: "m1", Agent: "claude", SessionID: "s1", DisplayName: "p",
			State: apitypes.StateWorking, UpdatedAt: t2,
		}},
	})
	list = s.ListSessions("m1")
	if list[0].StartedAt == nil || !list[0].StartedAt.Equal(t1) {
		t.Fatalf("stable working started=%v want %v", list[0].StartedAt, t1)
	}
	// leave working
	_, _ = s.ApplyReport(apitypes.ReportRequest{
		MachineID: "m1", MachineName: "desk", Platform: "linux", ReportedAt: t2.Add(time.Minute),
		Sessions: []apitypes.Session{{
			MachineID: "m1", Agent: "claude", SessionID: "s1", DisplayName: "p",
			State: apitypes.StateDone, UpdatedAt: t2.Add(time.Minute),
		}},
	})
	list = s.ListSessions("m1")
	if list[0].StartedAt != nil {
		t.Fatalf("non-working should clear started_at, got %v", list[0].StartedAt)
	}
	// re-enter working — new start
	_, _ = s.ApplyReport(apitypes.ReportRequest{
		MachineID: "m1", MachineName: "desk", Platform: "linux", ReportedAt: t3,
		Sessions: []apitypes.Session{{
			MachineID: "m1", Agent: "claude", SessionID: "s1", DisplayName: "p",
			State: apitypes.StateWorking, UpdatedAt: t3,
		}},
	})
	list = s.ListSessions("m1")
	if list[0].StartedAt == nil || !list[0].StartedAt.Equal(t3) {
		t.Fatalf("reenter working started=%v want %v", list[0].StartedAt, t3)
	}
}
