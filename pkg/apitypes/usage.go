package apitypes

import "time"

// UsageEvent is one normalized token usage atom from a monitor.
// input_tokens must already be channel-normalized (Codex: raw - cached).
type UsageEvent struct {
	DedupeKey         string    `json:"dedupe_key"`
	MachineID         string    `json:"machine_id,omitempty"`
	Agent             string    `json:"agent"` // claude | codex
	Model             string    `json:"model,omitempty"`
	SessionID         string    `json:"session_id,omitempty"`
	OccurredAt        time.Time `json:"occurred_at"`
	InputTokens       int64     `json:"input_tokens"`
	OutputTokens      int64     `json:"output_tokens"`
	ReasoningTokens   int64     `json:"reasoning_tokens,omitempty"`
	CacheWriteTokens  int64     `json:"cache_write_tokens,omitempty"`
	CacheHitTokens    int64     `json:"cache_hit_tokens,omitempty"`
}

// UsageReportRequest is a batch upsert from one machine.
type UsageReportRequest struct {
	MachineID   string       `json:"machine_id"`
	MachineName string       `json:"machine_name"`
	Platform    string       `json:"platform"`
	ReportedAt  time.Time    `json:"reported_at"`
	Events      []UsageEvent `json:"events"`
}

// UsageReportResponse is the batch upsert result.
type UsageReportResponse struct {
	OK         bool `json:"ok"`
	Accepted   int  `json:"accepted"`
	Duplicates int  `json:"duplicates"`
}

// UsageMetrics is aggregated token volume + estimated cost.
type UsageMetrics struct {
	InputTokens       int64    `json:"input_tokens"`
	OutputTokens      int64    `json:"output_tokens"`
	ReasoningTokens   int64    `json:"reasoning_tokens"`
	CacheWriteTokens  int64    `json:"cache_write_tokens"`
	CacheHitTokens    int64    `json:"cache_hit_tokens"`
	RealUsage         int64    `json:"real_usage"`
	CacheHitRate      *float64 `json:"cache_hit_rate"`
	EstimatedCostUSD  *float64 `json:"estimated_cost_usd"`
	EventCount        int64    `json:"event_count"`
	Priced            bool     `json:"priced"`
}

// UsageSummaryResponse is GET /api/v1/usage/summary.
type UsageSummaryResponse struct {
	From time.Time `json:"from"`
	To   time.Time `json:"to"`
	UsageMetrics
}

// UsageBreakdownGroup is one group row.
type UsageBreakdownGroup struct {
	Key string `json:"key"`
	UsageMetrics
}

// UsageBreakdownResponse is GET /api/v1/usage/breakdown.
type UsageBreakdownResponse struct {
	From    time.Time             `json:"from"`
	To      time.Time             `json:"to"`
	GroupBy string                `json:"group_by"`
	Groups  []UsageBreakdownGroup `json:"groups"`
}

// UsageQuery filters summary/breakdown queries.
type UsageQuery struct {
	From      time.Time
	To        time.Time
	MachineID string
	Agent     string
	Model     string
	GroupBy   string // agent | model | machine | day
}

// FillDerived sets real_usage and cache_hit_rate from component counters.
func (m *UsageMetrics) FillDerived() {
	out := m.OutputTokens + m.ReasoningTokens
	m.RealUsage = m.InputTokens + out + m.CacheWriteTokens + m.CacheHitTokens
	den := m.CacheHitTokens + m.CacheWriteTokens + m.InputTokens
	if den > 0 {
		rate := float64(m.CacheHitTokens) / float64(den)
		m.CacheHitRate = &rate
	} else {
		m.CacheHitRate = nil
	}
}

// Add accumulates another metrics row (no cost merge).
func (m *UsageMetrics) Add(o UsageMetrics) {
	m.InputTokens += o.InputTokens
	m.OutputTokens += o.OutputTokens
	m.ReasoningTokens += o.ReasoningTokens
	m.CacheWriteTokens += o.CacheWriteTokens
	m.CacheHitTokens += o.CacheHitTokens
	m.EventCount += o.EventCount
}
