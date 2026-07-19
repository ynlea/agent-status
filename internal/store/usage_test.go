package store

import (
	"path/filepath"
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
