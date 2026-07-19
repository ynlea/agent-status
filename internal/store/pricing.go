package store

import (
	"strings"
	"sync"

	"github.com/ynlea/agent-status/pkg/apitypes"
)

// Price sources for model_prices.source.
const (
	SourceBundled    = "bundled"
	SourceOverride   = "override"
	SourceOpenRouter = "openrouter"
)

// ModelPrice is USD per million tokens.
type ModelPrice struct {
	ModelID        string
	InputPerM      float64
	OutputPerM     float64
	CacheReadPerM  float64
	CacheWritePerM float64
	Source         string
}

// bundledPublicPrices are cold-start fallbacks (USD / 1M tokens).
var bundledPublicPrices = []ModelPrice{
	// Claude
	{ModelID: "claude-opus-4", InputPerM: 15, OutputPerM: 75, CacheReadPerM: 1.50, CacheWritePerM: 18.75},
	{ModelID: "claude-opus-4-1", InputPerM: 15, OutputPerM: 75, CacheReadPerM: 1.50, CacheWritePerM: 18.75},
	{ModelID: "claude-opus-4-5", InputPerM: 5, OutputPerM: 25, CacheReadPerM: 0.50, CacheWritePerM: 6.25},
	{ModelID: "claude-opus-4-6", InputPerM: 5, OutputPerM: 25, CacheReadPerM: 0.50, CacheWritePerM: 6.25},
	{ModelID: "claude-opus-4-7", InputPerM: 5, OutputPerM: 25, CacheReadPerM: 0.50, CacheWritePerM: 6.25},
	{ModelID: "claude-opus-4-8", InputPerM: 5, OutputPerM: 25, CacheReadPerM: 0.50, CacheWritePerM: 6.25},
	{ModelID: "claude-sonnet-4", InputPerM: 3, OutputPerM: 15, CacheReadPerM: 0.30, CacheWritePerM: 3.75},
	{ModelID: "claude-sonnet-4-5", InputPerM: 3, OutputPerM: 15, CacheReadPerM: 0.30, CacheWritePerM: 3.75},
	{ModelID: "claude-sonnet-4-6", InputPerM: 3, OutputPerM: 15, CacheReadPerM: 0.30, CacheWritePerM: 3.75},
	{ModelID: "claude-sonnet-5", InputPerM: 2, OutputPerM: 10, CacheReadPerM: 0.20, CacheWritePerM: 2.50},
	{ModelID: "claude-haiku-4-5", InputPerM: 1, OutputPerM: 5, CacheReadPerM: 0.10, CacheWritePerM: 1.25},
	{ModelID: "claude-3-5-sonnet", InputPerM: 3, OutputPerM: 15, CacheReadPerM: 0.30, CacheWritePerM: 3.75},
	{ModelID: "claude-3-5-haiku", InputPerM: 0.80, OutputPerM: 4, CacheReadPerM: 0.08, CacheWritePerM: 1.00},
	// OpenAI / Codex-ish
	{ModelID: "gpt-5", InputPerM: 1.25, OutputPerM: 10, CacheReadPerM: 0.125},
	{ModelID: "gpt-5-1", InputPerM: 1.25, OutputPerM: 10, CacheReadPerM: 0.125},
	{ModelID: "gpt-5-2", InputPerM: 1.75, OutputPerM: 14, CacheReadPerM: 0.175},
	{ModelID: "gpt-5-4", InputPerM: 2.50, OutputPerM: 15, CacheReadPerM: 0.25},
	{ModelID: "gpt-5-4-mini", InputPerM: 0.75, OutputPerM: 4.50, CacheReadPerM: 0.075},
	{ModelID: "gpt-5-4-nano", InputPerM: 0.20, OutputPerM: 1.25, CacheReadPerM: 0.02},
	{ModelID: "gpt-5-5", InputPerM: 5, OutputPerM: 30, CacheReadPerM: 0.50},
	{ModelID: "gpt-5-6", InputPerM: 1.25, OutputPerM: 10, CacheReadPerM: 0.125},
	{ModelID: "gpt-5-6-sol", InputPerM: 5, OutputPerM: 30, CacheReadPerM: 0.50},
	{ModelID: "gpt-5-6-terra", InputPerM: 2.50, OutputPerM: 15, CacheReadPerM: 0.25},
	{ModelID: "gpt-5-6-luna", InputPerM: 1, OutputPerM: 6, CacheReadPerM: 0.10},
	{ModelID: "gpt-5-codex", InputPerM: 1.25, OutputPerM: 10, CacheReadPerM: 0.125},
	{ModelID: "codex-mini-latest", InputPerM: 1.50, OutputPerM: 6, CacheReadPerM: 0.375},
}

// overridePublicPrices pin accurate list prices (esp. Claude cache). Never overwritten by openrouter.
var overridePublicPrices = []ModelPrice{
	{ModelID: "claude-opus-4-5", InputPerM: 5, OutputPerM: 25, CacheReadPerM: 0.50, CacheWritePerM: 6.25},
	{ModelID: "claude-opus-4-6", InputPerM: 5, OutputPerM: 25, CacheReadPerM: 0.50, CacheWritePerM: 6.25},
	{ModelID: "claude-opus-4-7", InputPerM: 5, OutputPerM: 25, CacheReadPerM: 0.50, CacheWritePerM: 6.25},
	{ModelID: "claude-opus-4-8", InputPerM: 5, OutputPerM: 25, CacheReadPerM: 0.50, CacheWritePerM: 6.25},
	{ModelID: "claude-sonnet-4", InputPerM: 3, OutputPerM: 15, CacheReadPerM: 0.30, CacheWritePerM: 3.75},
	{ModelID: "claude-sonnet-4-5", InputPerM: 3, OutputPerM: 15, CacheReadPerM: 0.30, CacheWritePerM: 3.75},
	{ModelID: "claude-sonnet-4-6", InputPerM: 3, OutputPerM: 15, CacheReadPerM: 0.30, CacheWritePerM: 3.75},
	{ModelID: "claude-sonnet-5", InputPerM: 2, OutputPerM: 10, CacheReadPerM: 0.20, CacheWritePerM: 2.50},
	{ModelID: "claude-haiku-4-5", InputPerM: 1, OutputPerM: 5, CacheReadPerM: 0.10, CacheWritePerM: 1.25},
}

// priceCache is the in-process price index (store-owned).
type priceCache struct {
	mu    sync.RWMutex
	byID  map[string]ModelPrice
	order []string // stable iteration for tests
}

func newPriceCache() *priceCache {
	return &priceCache{byID: make(map[string]ModelPrice)}
}

// canReplace reports whether incoming source may replace existing source.
func canReplace(existing, incoming string) bool {
	if existing == "" {
		return true
	}
	if existing == SourceOverride && incoming != SourceOverride {
		return false
	}
	return true
}

func (c *priceCache) upsert(p ModelPrice, source string) bool {
	id := NormalizeModelID(p.ModelID)
	if id == "" {
		return false
	}
	p.ModelID = id
	if source == "" {
		source = SourceBundled
	}
	p.Source = source

	c.mu.Lock()
	defer c.mu.Unlock()
	if old, ok := c.byID[id]; ok && !canReplace(old.Source, source) {
		return false
	}
	if _, ok := c.byID[id]; !ok {
		c.order = append(c.order, id)
	}
	// Preserve non-zero cache fields when openrouter only has input/output.
	if source == SourceOpenRouter {
		if old, ok := c.byID[id]; ok {
			if p.CacheReadPerM == 0 && old.CacheReadPerM != 0 {
				p.CacheReadPerM = old.CacheReadPerM
			}
			if p.CacheWritePerM == 0 && old.CacheWritePerM != 0 {
				p.CacheWritePerM = old.CacheWritePerM
			}
		}
	}
	c.byID[id] = p
	return true
}

func (c *priceCache) lookup(model string) (ModelPrice, bool) {
	id := NormalizeModelID(model)
	if id == "" {
		return ModelPrice{}, false
	}
	c.mu.RLock()
	defer c.mu.RUnlock()
	if p, ok := c.byID[id]; ok {
		return p, true
	}
	// longest ModelID match by prefix/contains
	bestLen := 0
	var best ModelPrice
	found := false
	for mid, p := range c.byID {
		if strings.HasPrefix(id, mid) || strings.Contains(id, mid) {
			if len(mid) > bestLen {
				best = p
				bestLen = len(mid)
				found = true
			}
		}
	}
	return best, found
}

func (c *priceCache) snapshot() []ModelPrice {
	c.mu.RLock()
	defer c.mu.RUnlock()
	out := make([]ModelPrice, 0, len(c.byID))
	for _, id := range c.order {
		if p, ok := c.byID[id]; ok {
			out = append(out, p)
		}
	}
	// include any not in order (defensive)
	for id, p := range c.byID {
		seen := false
		for _, o := range c.order {
			if o == id {
				seen = true
				break
			}
		}
		if !seen {
			out = append(out, p)
		}
	}
	return out
}

func (c *priceCache) loadAll(rows []ModelPrice) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.byID = make(map[string]ModelPrice, len(rows))
	c.order = c.order[:0]
	for _, p := range rows {
		id := NormalizeModelID(p.ModelID)
		if id == "" {
			continue
		}
		p.ModelID = id
		if _, ok := c.byID[id]; !ok {
			c.order = append(c.order, id)
		}
		c.byID[id] = p
	}
}

// NormalizeModelID strips common wrappers for price lookup.
func NormalizeModelID(raw string) string {
	s := strings.TrimSpace(strings.ToLower(raw))
	if s == "" || s == "unknown" || s == "<synthetic>" {
		return ""
	}
	if i := strings.LastIndex(s, "/"); i >= 0 {
		s = s[i+1:]
	}
	if i := strings.Index(s, ":"); i >= 0 {
		s = s[:i]
	}
	s = strings.ReplaceAll(s, "@", "-")
	s = strings.ReplaceAll(s, ".", "-")
	s = strings.TrimSuffix(s, "[1m]")
	// drop trailing -YYYYMMDD
	parts := strings.Split(s, "-")
	if len(parts) >= 2 {
		last := parts[len(parts)-1]
		if len(last) == 8 && isAllDigit(last) {
			s = strings.Join(parts[:len(parts)-1], "-")
		}
	}
	// collapse duplicate dashes
	for strings.Contains(s, "--") {
		s = strings.ReplaceAll(s, "--", "-")
	}
	return strings.Trim(s, "-")
}

func isAllDigit(s string) bool {
	for _, r := range s {
		if r < '0' || r > '9' {
			return false
		}
	}
	return len(s) > 0
}

// LookupModelPrice finds the best matching price in the package default cache (tests / legacy).
// Prefer Store.LookupModelPrice after a store is constructed.
func LookupModelPrice(model string) (ModelPrice, bool) {
	return defaultPriceCache.lookup(model)
}

// defaultPriceCache backs package-level Lookup for tests before a Store is used.
var defaultPriceCache = func() *priceCache {
	c := newPriceCache()
	for _, p := range bundledPublicPrices {
		c.upsert(p, SourceBundled)
	}
	for _, p := range overridePublicPrices {
		c.upsert(p, SourceOverride)
	}
	return c
}()

// EstimateCostUSD returns cost and whether a price was found (package default cache).
func EstimateCostUSD(model string, m apitypes.UsageMetrics) (float64, bool) {
	return EstimateCostUSDLookup(LookupModelPrice, model, m)
}

// PriceLookup resolves a model string to a unit price.
type PriceLookup func(model string) (ModelPrice, bool)

// EstimateCostUSDLookup estimates cost using the provided lookup.
func EstimateCostUSDLookup(lookup PriceLookup, model string, m apitypes.UsageMetrics) (float64, bool) {
	if lookup == nil {
		lookup = LookupModelPrice
	}
	p, ok := lookup(model)
	if !ok {
		return 0, false
	}
	out := float64(m.OutputTokens+m.ReasoningTokens) / 1e6 * p.OutputPerM
	in := float64(m.InputTokens) / 1e6 * p.InputPerM
	cr := float64(m.CacheHitTokens) / 1e6 * p.CacheReadPerM
	cw := float64(m.CacheWriteTokens) / 1e6 * p.CacheWritePerM
	return in + out + cr + cw, true
}

// ApplyCost fills EstimatedCostUSD / Priced on metrics for a single model key.
func ApplyCost(model string, m *apitypes.UsageMetrics) {
	ApplyCostLookup(LookupModelPrice, model, m)
}

// ApplyCostLookup is ApplyCost with a custom lookup.
func ApplyCostLookup(lookup PriceLookup, model string, m *apitypes.UsageMetrics) {
	cost, ok := EstimateCostUSDLookup(lookup, model, *m)
	if !ok {
		m.EstimatedCostUSD = nil
		m.Priced = false
		return
	}
	m.EstimatedCostUSD = &cost
	m.Priced = true
}

// FinishMetrics sets derived fields without model-specific cost.
func FinishMetrics(m *apitypes.UsageMetrics) {
	m.FillDerived()
}
