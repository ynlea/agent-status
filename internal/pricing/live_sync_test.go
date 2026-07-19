package pricing

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/ynlea/agent-status/internal/store"
)

// Live smoke: go test ./internal/pricing/ -run TestLiveOpenRouterSync -count=1 -v
func TestLiveOpenRouterSync(t *testing.T) {
	if os.Getenv("SKIP_LIVE_OPENROUTER") == "1" {
		t.Skip("SKIP_LIVE_OPENROUTER=1")
	}
	m := store.NewMemory(10)
	before := len(m.ListModelPrices())
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()
	res, err := SyncOpenRouter(ctx, Config{
		BaseURL: envOr("OPENROUTER_API_URL", "https://openrouter.ai/api/v1"),
		APIKey:  os.Getenv("OPENROUTER_API_KEY"),
	}, m)
	if err != nil {
		t.Fatalf("sync: %v", err)
	}
	after := len(m.ListModelPrices())
	t.Logf("fetched=%d upserted=%d skipped=%d prices %d -> %d", res.Fetched, res.Upserted, res.Skipped, before, after)
	if res.Fetched < 10 {
		t.Fatalf("expected many models, fetched=%d", res.Fetched)
	}
	if after <= before {
		t.Fatalf("expected price table to grow: before=%d after=%d", before, after)
	}
	// override must remain for sonnet
	p, ok := m.LookupModelPrice("claude-sonnet-4-5")
	if !ok {
		t.Fatal("missing claude-sonnet-4-5")
	}
	if p.Source != store.SourceOverride {
		t.Fatalf("override lost, source=%s", p.Source)
	}
	if p.CacheReadPerM <= 0 {
		t.Fatalf("cache read missing: %+v", p)
	}
	// some openrouter model should exist beyond seed
	if _, ok := m.LookupModelPrice("gpt-4o-mini"); !ok {
		// try common aliases
		if _, ok2 := m.LookupModelPrice("openai/gpt-4o-mini"); !ok2 {
			t.Log("gpt-4o-mini not found (name may have changed); listing sample openrouter sources")
			n := 0
			for _, row := range m.ListModelPrices() {
				if row.Source == store.SourceOpenRouter {
					t.Logf("  sample openrouter: %s in=%.4f out=%.4f", row.ModelID, row.InputPerM, row.OutputPerM)
					n++
					if n >= 5 {
						break
					}
				}
			}
			if n == 0 {
				t.Fatal("no openrouter-sourced rows after sync")
			}
		}
	}
}

func envOr(k, d string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return d
}
