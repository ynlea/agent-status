package store

import (
	"sort"
	"strings"

	"github.com/ynlea/agent-status/pkg/apitypes"
)

func globalDedupeKey(machineID, key string) string {
	key = strings.TrimSpace(key)
	if key == "" {
		return ""
	}
	if strings.HasPrefix(key, machineID+":") {
		return key
	}
	return machineID + ":" + key
}

func sanitizeUsageEvent(machineID string, e apitypes.UsageEvent) (apitypes.UsageEvent, bool) {
	e.DedupeKey = globalDedupeKey(machineID, e.DedupeKey)
	if e.DedupeKey == "" {
		return e, false
	}
	e.MachineID = machineID
	e.Agent = strings.ToLower(strings.TrimSpace(e.Agent))
	if e.Agent != "claude" && e.Agent != "codex" {
		return e, false
	}
	if e.OccurredAt.IsZero() {
		return e, false
	}
	if e.InputTokens < 0 || e.OutputTokens < 0 || e.ReasoningTokens < 0 || e.CacheWriteTokens < 0 || e.CacheHitTokens < 0 {
		return e, false
	}
	// skip empty zero events that carry no signal
	if e.InputTokens == 0 && e.OutputTokens == 0 && e.ReasoningTokens == 0 && e.CacheWriteTokens == 0 && e.CacheHitTokens == 0 {
		// still accept for bookkeeping of "seen" turns? design said token counts — skip pure zeros
		return e, false
	}
	if e.Model == "" {
		e.Model = "unknown"
	}
	return e, true
}

func metricsFromParts(in, out, reason, cw, ch, n int64) apitypes.UsageMetrics {
	m := apitypes.UsageMetrics{
		InputTokens:      in,
		OutputTokens:     out,
		ReasoningTokens:  reason,
		CacheWriteTokens: cw,
		CacheHitTokens:   ch,
		EventCount:       n,
	}
	m.FillDerived()
	return m
}

func emptySummary(q apitypes.UsageQuery) apitypes.UsageSummaryResponse {
	m := metricsFromParts(0, 0, 0, 0, 0, 0)
	cost := 0.0
	m.EstimatedCostUSD = &cost
	m.Priced = true
	return apitypes.UsageSummaryResponse{From: q.From, To: q.To, UsageMetrics: m}
}

func finalizeSummaryFromModelMap(lookup PriceLookup, q apitypes.UsageQuery, byModel map[string]apitypes.UsageMetrics) apitypes.UsageSummaryResponse {
	var total apitypes.UsageMetrics
	var costSum float64
	allPriced := true
	any := false
	for model, m := range byModel {
		any = true
		total.Add(m)
		c, ok := EstimateCostUSDLookup(lookup, model, m)
		if ok {
			costSum += c
		} else {
			allPriced = false
		}
	}
	if !any {
		return emptySummary(q)
	}
	total.FillDerived()
	if allPriced {
		total.EstimatedCostUSD = &costSum
		total.Priced = true
	} else if costSum > 0 {
		total.EstimatedCostUSD = &costSum
		total.Priced = false
	} else {
		total.EstimatedCostUSD = nil
		total.Priced = false
	}
	return apitypes.UsageSummaryResponse{From: q.From, To: q.To, UsageMetrics: total}
}

func groupKey(e apitypes.UsageEvent, groupBy string) string {
	switch strings.ToLower(groupBy) {
	case "agent":
		return e.Agent
	case "machine":
		return e.MachineID
	case "day":
		return e.OccurredAt.UTC().Format("2006-01-02")
	case "hour":
		return e.OccurredAt.UTC().Format("2006-01-02T15")
	default: // model
		return e.Model
	}
}

func finalizeBreakdown(lookup PriceLookup, q apitypes.UsageQuery, groupBy string, groups map[string]map[string]apitypes.UsageMetrics) apitypes.UsageBreakdownResponse {
	// groups[groupKey][model]metrics — cost always by model then sum
	out := make([]apitypes.UsageBreakdownGroup, 0, len(groups))
	for key, byModel := range groups {
		var total apitypes.UsageMetrics
		var costSum float64
		allPriced := true
		for model, m := range byModel {
			total.Add(m)
			c, ok := EstimateCostUSDLookup(lookup, model, m)
			if ok {
				costSum += c
			} else {
				allPriced = false
			}
		}
		total.FillDerived()
		if allPriced && total.EventCount > 0 {
			total.EstimatedCostUSD = &costSum
			total.Priced = true
		} else if costSum > 0 {
			total.EstimatedCostUSD = &costSum
			total.Priced = false
		}
		// when groupBy is model, single model key — ApplyCost for clearer priced flag
		if groupBy == "model" {
			ApplyCostLookup(lookup, key, &total)
		}
		out = append(out, apitypes.UsageBreakdownGroup{Key: key, UsageMetrics: total})
	}
	sort.Slice(out, func(i, j int) bool {
		// time buckets keep chronological order for charts
		if groupBy == "day" || groupBy == "hour" {
			return out[i].Key < out[j].Key
		}
		if out[i].RealUsage == out[j].RealUsage {
			return out[i].Key < out[j].Key
		}
		return out[i].RealUsage > out[j].RealUsage
	})
	if out == nil {
		out = []apitypes.UsageBreakdownGroup{}
	}
	return apitypes.UsageBreakdownResponse{
		From:    q.From,
		To:      q.To,
		GroupBy: groupBy,
		Groups:  out,
	}
}

func eventMatches(e apitypes.UsageEvent, q apitypes.UsageQuery) bool {
	if !q.From.IsZero() && e.OccurredAt.Before(q.From) {
		return false
	}
	if !q.To.IsZero() && e.OccurredAt.After(q.To) {
		return false
	}
	if q.MachineID != "" && e.MachineID != q.MachineID {
		return false
	}
	if q.Agent != "" && !strings.EqualFold(e.Agent, q.Agent) {
		return false
	}
	if q.Model != "" && e.Model != q.Model && NormalizeModelID(e.Model) != NormalizeModelID(q.Model) {
		return false
	}
	return true
}

func addEventToModelMap(byModel map[string]apitypes.UsageMetrics, e apitypes.UsageEvent) {
	m := byModel[e.Model]
	m.InputTokens += e.InputTokens
	m.OutputTokens += e.OutputTokens
	m.ReasoningTokens += e.ReasoningTokens
	m.CacheWriteTokens += e.CacheWriteTokens
	m.CacheHitTokens += e.CacheHitTokens
	m.EventCount++
	byModel[e.Model] = m
}

func validateGroupBy(g string) string {
	switch strings.ToLower(strings.TrimSpace(g)) {
	case "agent", "model", "machine", "day", "hour":
		return strings.ToLower(g)
	default:
		return "model"
	}
}
