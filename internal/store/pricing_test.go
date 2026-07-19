package store

import (
	"path/filepath"
	"testing"

	"github.com/ynlea/agent-status/pkg/apitypes"
)

func TestNormalizeModelIDOpenRouterStyle(t *testing.T) {
	cases := map[string]string{
		"anthropic/claude-sonnet-4.5":    "claude-sonnet-4-5",
		"claude-sonnet-4-5-20250929":     "claude-sonnet-4-5",
		"openai/gpt-5.4":                 "gpt-5-4",
		"gpt-5.2":                        "gpt-5-2",
		"anthropic/claude-opus-4.7:beta": "claude-opus-4-7",
	}
	for in, want := range cases {
		if got := NormalizeModelID(in); got != want {
			t.Fatalf("%q => %q want %q", in, got, want)
		}
	}
}

func TestOverrideNotClobberedByOpenRouter(t *testing.T) {
	path := filepath.Join(t.TempDir(), "p.db")
	s, err := NewSQLite(path)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()

	// override seeded for sonnet
	p, ok := s.LookupModelPrice("claude-sonnet-4-5-20250929")
	if !ok || p.CacheReadPerM == 0 {
		t.Fatalf("expected override cache price, got %+v ok=%v", p, ok)
	}
	wantCache := p.CacheReadPerM

	err = s.UpsertModelPrice(ModelPrice{
		ModelID: "claude-sonnet-4-5", InputPerM: 99, OutputPerM: 99,
	}, SourceOpenRouter)
	if err != nil {
		t.Fatal(err)
	}
	p2, ok := s.LookupModelPrice("claude-sonnet-4-5")
	if !ok {
		t.Fatal("missing price")
	}
	if p2.InputPerM == 99 {
		t.Fatalf("openrouter overwrote override: %+v", p2)
	}
	if p2.CacheReadPerM != wantCache {
		t.Fatalf("cache read changed: %+v", p2)
	}
	if p2.Source != SourceOverride {
		t.Fatalf("source=%s", p2.Source)
	}
}

func TestOpenRouterUpsertAndLookup(t *testing.T) {
	m := NewMemory(10)
	err := m.UpsertModelPrice(ModelPrice{
		ModelID: "openai/gpt-5.4-mini", InputPerM: 0.75, OutputPerM: 4.5, CacheReadPerM: 0.075,
	}, SourceOpenRouter)
	if err != nil {
		t.Fatal(err)
	}
	p, ok := m.LookupModelPrice("gpt-5.4-mini")
	if !ok {
		t.Fatal("not found")
	}
	if p.InputPerM != 0.75 || p.OutputPerM != 4.5 {
		t.Fatalf("%+v", p)
	}
	cost, ok := EstimateCostUSDLookup(m.LookupModelPrice, "gpt-5.4-mini", apitypes.UsageMetrics{
		InputTokens: 1_000_000, OutputTokens: 1_000_000,
	})
	if !ok || cost < 5.0 || cost > 5.5 {
		t.Fatalf("cost=%v ok=%v", cost, ok)
	}
}

func TestCacheCostWithOverride(t *testing.T) {
	m := NewMemory(10)
	// haiku override: in 1 out 5 cache_read 0.1
	cost, ok := EstimateCostUSDLookup(m.LookupModelPrice, "claude-haiku-4-5", apitypes.UsageMetrics{
		InputTokens: 1_000_000, CacheHitTokens: 1_000_000,
	})
	if !ok {
		t.Fatal("no price")
	}
	// 1 + 0.1 = 1.1
	if cost < 1.09 || cost > 1.11 {
		t.Fatalf("cost=%v", cost)
	}
}
