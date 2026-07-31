package monitor

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestParseClaudeUsageFile(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "sess.jsonl")
	content := `{"type":"user","timestamp":"2026-07-19T10:00:00Z"}
{"type":"assistant","timestamp":"2026-07-19T10:00:01Z","sessionId":"s1","message":{"id":"msg_1","role":"assistant","model":"claude-sonnet-4-5","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":100}}}
{"type":"assistant","timestamp":"2026-07-19T10:00:02Z","sessionId":"s1","message":{"id":"msg_1","role":"assistant","model":"claude-sonnet-4-5","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":100}}}
`
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	ev, off, err := ParseClaudeUsageFile(p, 0)
	if err != nil {
		t.Fatal(err)
	}
	if len(ev) != 1 {
		t.Fatalf("want 1 event after dedupe, got %d", len(ev))
	}
	if ev[0].InputTokens != 10 || ev[0].CacheHitTokens != 100 {
		t.Fatalf("ev=%+v", ev[0])
	}
	// incremental: no new lines
	ev2, _, err := ParseClaudeUsageFile(p, off)
	if err != nil {
		t.Fatal(err)
	}
	if len(ev2) != 0 {
		t.Fatalf("want 0 new, got %d", len(ev2))
	}
}

func TestParseCodexUsageFile(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "rollout-demo.jsonl")
	content := `{"timestamp":"2026-07-19T10:00:00Z","type":"session_meta","payload":{"originator":"codex"}}
{"timestamp":"2026-07-19T10:00:01Z","type":"turn_context","payload":{"model":"gpt-5.2"}}
{"timestamp":"2026-07-19T10:00:02Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":800,"output_tokens":20,"reasoning_output_tokens":5},"total_token_usage":{"input_tokens":1000,"cached_input_tokens":800,"output_tokens":20,"reasoning_output_tokens":5}}}}
`
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	ev, off, lastModel, lastTotal, err := ParseCodexUsageFile(p, 0, "", codexTotalBaseline{}, 0)
	if err != nil {
		t.Fatal(err)
	}
	if len(ev) != 1 {
		t.Fatalf("want 1, got %d", len(ev))
	}
	// billed = 1000-800
	if ev[0].InputTokens != 200 || ev[0].CacheHitTokens != 800 || ev[0].ReasoningTokens != 5 {
		t.Fatalf("ev=%+v", ev[0])
	}
	if ev[0].Model != "gpt-5.2" {
		t.Fatalf("model=%s", ev[0].Model)
	}
	if lastModel != "gpt-5.2" {
		t.Fatalf("lastModel=%s", lastModel)
	}
	if !lastTotal.Valid || lastTotal.Input != 1000 || lastTotal.Cached != 800 {
		t.Fatalf("lastTotal=%+v", lastTotal)
	}

	// Append another token_count without a new turn_context; incremental parse
	// must keep model via startModel / prefix recovery and delta total.
	extra := `{"timestamp":"2026-07-19T10:00:03Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":0,"output_tokens":10,"reasoning_output_tokens":0},"total_token_usage":{"input_tokens":1100,"cached_input_tokens":800,"output_tokens":30,"reasoning_output_tokens":5}}}}
`
	f, err := os.OpenFile(p, os.O_APPEND|os.O_WRONLY, 0)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := f.WriteString(extra); err != nil {
		t.Fatal(err)
	}
	_ = f.Close()

	ev2, _, last2, lastTotal2, err := ParseCodexUsageFile(p, off, lastModel, lastTotal, 0)
	if err != nil {
		t.Fatal(err)
	}
	if len(ev2) != 1 || ev2[0].Model != "gpt-5.2" {
		t.Fatalf("incremental with startModel: %+v last=%s", ev2, last2)
	}
	// delta input 100, cached 0, out 10
	if ev2[0].InputTokens != 100 || ev2[0].CacheHitTokens != 0 || ev2[0].OutputTokens != 10 {
		t.Fatalf("delta ev=%+v", ev2[0])
	}
	if !lastTotal2.Valid || lastTotal2.Input != 1100 {
		t.Fatalf("lastTotal2=%+v", lastTotal2)
	}

	// Without startModel/startTotal, mid-file parse should recover both from prefix.
	ev3, _, last3, _, err := ParseCodexUsageFile(p, off, "", codexTotalBaseline{}, 0)
	if err != nil {
		t.Fatal(err)
	}
	if len(ev3) != 1 || ev3[0].Model != "gpt-5.2" {
		t.Fatalf("incremental with prefix recovery: %+v last=%s", ev3, last3)
	}
	if ev3[0].InputTokens != 100 || ev3[0].OutputTokens != 10 {
		t.Fatalf("prefix-recovered delta should not re-emit full total: %+v", ev3[0])
	}
}

func TestParseCodexUsageFileSkipsUnchangedTotal(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "rollout-dup.jsonl")
	content := `{"timestamp":"2026-07-19T10:00:00Z","type":"turn_context","payload":{"model":"gpt-5.2"}}
{"timestamp":"2026-07-19T10:00:01Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":500,"cached_input_tokens":100,"output_tokens":20,"reasoning_output_tokens":0},"total_token_usage":{"input_tokens":500,"cached_input_tokens":100,"output_tokens":20,"reasoning_output_tokens":0}}}}
{"timestamp":"2026-07-19T10:00:02Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":500,"cached_input_tokens":100,"output_tokens":20,"reasoning_output_tokens":0},"total_token_usage":{"input_tokens":500,"cached_input_tokens":100,"output_tokens":20,"reasoning_output_tokens":0}}}}
{"timestamp":"2026-07-19T10:00:03Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":500,"cached_input_tokens":100,"output_tokens":20,"reasoning_output_tokens":0},"total_token_usage":{"input_tokens":500,"cached_input_tokens":100,"output_tokens":20,"reasoning_output_tokens":0}}}}
`
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	ev, _, _, _, err := ParseCodexUsageFile(p, 0, "", codexTotalBaseline{}, 0)
	if err != nil {
		t.Fatal(err)
	}
	if len(ev) != 1 {
		t.Fatalf("unchanged total must not re-count last; want 1 got %d", len(ev))
	}
	if ev[0].InputTokens != 400 || ev[0].CacheHitTokens != 100 {
		t.Fatalf("ev=%+v", ev[0])
	}
}

func TestParseCodexUsageFileLastOnlyFallback(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "rollout-last-only.jsonl")
	content := `{"timestamp":"2026-07-19T10:00:00Z","type":"turn_context","payload":{"model":"gpt-5.2"}}
{"timestamp":"2026-07-19T10:00:01Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":120,"cached_input_tokens":20,"output_tokens":7,"reasoning_output_tokens":1}}}}
`
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	ev, _, _, lastTotal, err := ParseCodexUsageFile(p, 0, "", codexTotalBaseline{}, 0)
	if err != nil {
		t.Fatal(err)
	}
	if len(ev) != 1 {
		t.Fatalf("want 1, got %d", len(ev))
	}
	if ev[0].InputTokens != 100 || ev[0].CacheHitTokens != 20 || ev[0].OutputTokens != 7 || ev[0].ReasoningTokens != 1 {
		t.Fatalf("ev=%+v", ev[0])
	}
	if lastTotal.Valid {
		t.Fatalf("last-only path should not invent total baseline: %+v", lastTotal)
	}
}

func TestParseCodexUsageFileClampsCached(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "rollout-clamp.jsonl")
	content := `{"timestamp":"2026-07-19T10:00:01Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":50,"cached_input_tokens":80,"output_tokens":1,"reasoning_output_tokens":0}}}}
`
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	ev, _, _, _, err := ParseCodexUsageFile(p, 0, "", codexTotalBaseline{}, 0)
	if err != nil {
		t.Fatal(err)
	}
	if len(ev) != 1 {
		t.Fatalf("want 1, got %d", len(ev))
	}
	if ev[0].InputTokens != 0 || ev[0].CacheHitTokens != 50 {
		t.Fatalf("cached should clamp to raw input: %+v", ev[0])
	}
}

func TestParseCodexUsageFileMultiSegmentDeltas(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "rollout-multi.jsonl")
	// three totals: 0→100/10/5/1, →250/30/15/3, →250/30/15/3 (unchanged skip), →400/50/20/4
	content := `{"timestamp":"2026-07-19T10:00:00Z","type":"turn_context","payload":{"model":"gpt-5.2"}}
{"timestamp":"2026-07-19T10:00:01Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":10,"output_tokens":5,"reasoning_output_tokens":1},"total_token_usage":{"input_tokens":100,"cached_input_tokens":10,"output_tokens":5,"reasoning_output_tokens":1}}}}
{"timestamp":"2026-07-19T10:00:02Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":150,"cached_input_tokens":20,"output_tokens":10,"reasoning_output_tokens":2},"total_token_usage":{"input_tokens":250,"cached_input_tokens":30,"output_tokens":15,"reasoning_output_tokens":3}}}}
{"timestamp":"2026-07-19T10:00:03Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":150,"cached_input_tokens":20,"output_tokens":10,"reasoning_output_tokens":2},"total_token_usage":{"input_tokens":250,"cached_input_tokens":30,"output_tokens":15,"reasoning_output_tokens":3}}}}
{"timestamp":"2026-07-19T10:00:04Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":150,"cached_input_tokens":20,"output_tokens":5,"reasoning_output_tokens":1},"total_token_usage":{"input_tokens":400,"cached_input_tokens":50,"output_tokens":20,"reasoning_output_tokens":4}}}}
`
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	ev, _, _, lastTotal, err := ParseCodexUsageFile(p, 0, "", codexTotalBaseline{}, 0)
	if err != nil {
		t.Fatal(err)
	}
	if len(ev) != 3 {
		t.Fatalf("want 3 deltas (skip unchanged), got %d", len(ev))
	}
	// billed = rawIn - cached per segment: 90, 130, 130
	var sumIn, sumCache, sumOut, sumReason int64
	for _, e := range ev {
		sumIn += e.InputTokens
		sumCache += e.CacheHitTokens
		sumOut += e.OutputTokens
		sumReason += e.ReasoningTokens
	}
	// final total relative to empty start: in 400, cache 50, out 20, reason 4 → billed 350
	if sumIn != 350 || sumCache != 50 || sumOut != 20 || sumReason != 4 {
		t.Fatalf("sum billed/cache/out/reason = %d/%d/%d/%d want 350/50/20/4; events=%+v", sumIn, sumCache, sumOut, sumReason, ev)
	}
	if !lastTotal.Valid || lastTotal.Input != 400 || lastTotal.Cached != 50 || lastTotal.Output != 20 || lastTotal.Reasoning != 4 {
		t.Fatalf("lastTotal=%+v", lastTotal)
	}
}



func TestCodexReplayPrefixSkip(t *testing.T) {
	dir := t.TempDir()
	parentID := "019f0000-0000-0000-0000-000000000001"
	childID := "019f0000-0000-0000-0000-000000000002"
	parent := filepath.Join(dir, "rollout-2026-07-28T10-00-00-"+parentID+".jsonl")
	child := filepath.Join(dir, "rollout-2026-07-28T10-01-00-"+childID+".jsonl")
	parentBody := strings.Join([]string{
		fmt.Sprintf(`{"timestamp":"2026-07-28T10:00:00Z","type":"session_meta","payload":{"id":"%s","session_id":"%s"}}`, parentID, parentID),
		`{"timestamp":"2026-07-28T10:00:01Z","type":"turn_context","payload":{"model":"gpt-5.2"}}`,
		`{"timestamp":"2026-07-28T10:00:02Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":800,"output_tokens":10,"reasoning_output_tokens":0}}}}`,
		`{"timestamp":"2026-07-28T10:00:03Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1500,"cached_input_tokens":1000,"output_tokens":20,"reasoning_output_tokens":0}}}}`,
	}, "\n") + "\n"
	childBody := strings.Join([]string{
		fmt.Sprintf(`{"timestamp":"2026-07-28T10:01:00Z","type":"session_meta","payload":{"id":"%s","session_id":"%s","thread_source":"subagent","parent_thread_id":"%s","forked_from_id":"%s"}}`, childID, parentID, parentID, parentID),
		`{"timestamp":"2026-07-28T10:01:01Z","type":"turn_context","payload":{"model":"gpt-5.2"}}`,
		`{"timestamp":"2026-07-28T10:01:02Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":800,"output_tokens":10,"reasoning_output_tokens":0}}}}`,
		`{"timestamp":"2026-07-28T10:01:03Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1500,"cached_input_tokens":1000,"output_tokens":20,"reasoning_output_tokens":0}}}}`,
		`{"timestamp":"2026-07-28T10:01:04Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1800,"cached_input_tokens":1200,"output_tokens":30,"reasoning_output_tokens":0}}}}`,
	}, "\n") + "\n"
	if err := os.WriteFile(parent, []byte(parentBody), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(child, []byte(childBody), 0o644); err != nil {
		t.Fatal(err)
	}
	idx := buildCodexRootRolloutIndex([]string{parent, child})
	if idx[parentID] != parent {
		t.Fatalf("root index=%v", idx)
	}
	skip := codexReplaySkipCount(child, idx)
	if skip != 2 {
		t.Fatalf("skip=%d want 2", skip)
	}
	evAll, _, _, _, err := ParseCodexUsageFile(child, 0, "", codexTotalBaseline{}, 0)
	if err != nil {
		t.Fatal(err)
	}
	var sumIn int64
	for _, e := range evAll {
		sumIn += e.InputTokens
	}
	ev, _, _, _, err := ParseCodexUsageFile(child, 0, "", codexTotalBaseline{}, skip)
	if err != nil {
		t.Fatal(err)
	}
	if len(ev) != 1 {
		t.Fatalf("want 1 event after replay skip, got %d (%+v)", len(ev), ev)
	}
	if ev[0].InputTokens != 100 || ev[0].CacheHitTokens != 200 || ev[0].OutputTokens != 10 {
		t.Fatalf("ev=%+v", ev[0])
	}
	if sumIn <= ev[0].InputTokens {
		t.Fatalf("unskipped sum should be larger: all=%d skipped=%d", sumIn, ev[0].InputTokens)
	}
}

func TestMatchingCodexReplayPrefix(t *testing.T) {
	parent := []codexTokenSig{{In: 1, HasTotal: true}, {In: 2, HasTotal: true}, {In: 3, HasTotal: true}}
	child := []codexTokenSig{{In: 1, HasTotal: true}, {In: 2, HasTotal: true}, {In: 9, HasTotal: true}}
	if n := matchingCodexReplayPrefix(child, parent); n != 2 {
		t.Fatalf("n=%d", n)
	}
	if n := matchingCodexReplayPrefix(child, nil); n != 0 {
		t.Fatalf("empty parent n=%d", n)
	}
}



func TestParseCodexUsageFileDecreasingTotalNoReemit(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "rollout-dip.jsonl")
	content := "" +
		`{"timestamp":"2026-07-28T10:00:00Z","type":"turn_context","payload":{"model":"gpt-5.2"}}` + "\n" +
		`{"timestamp":"2026-07-28T10:00:01Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":100,"output_tokens":10,"reasoning_output_tokens":0}}}}` + "\n" +
		`{"timestamp":"2026-07-28T10:00:02Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":800,"cached_input_tokens":50,"output_tokens":5,"reasoning_output_tokens":0}}}}` + "\n" +
		`{"timestamp":"2026-07-28T10:00:03Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1200,"cached_input_tokens":150,"output_tokens":15,"reasoning_output_tokens":0}}}}` + "\n"
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	ev, _, lastModel, _, err := ParseCodexUsageFile(path, 0, "", codexTotalBaseline{}, 0)
	if err != nil {
		t.Fatal(err)
	}
	if lastModel != "gpt-5.2" {
		t.Fatalf("model=%s", lastModel)
	}
	var sumIn, sumOut, sumCache int64
	for _, e := range ev {
		sumIn += e.InputTokens
		sumOut += e.OutputTokens
		sumCache += e.CacheHitTokens
		if e.Model != "gpt-5.2" {
			t.Fatalf("wrong model: %+v", e)
		}
	}
	if sumIn > 2000 {
		t.Fatalf("sumIn=%d looks like full re-emit on dip; events=%+v", sumIn, ev)
	}
	if sumIn != 1200 {
		t.Fatalf("sumIn=%d want 1200 events=%+v", sumIn, ev)
	}
	if sumCache != 200 {
		t.Fatalf("sumCache=%d want 200", sumCache)
	}
	if sumOut != 20 {
		t.Fatalf("sumOut=%d want 20", sumOut)
	}
}

func TestParsePiUsageFile(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "2026-07-31T10-00-00-000Z_019fb7a3-1931-736f-95d7-36ae8e298e4a.jsonl")
	content := `{"type":"session","version":3,"id":"019fb7a3-1931-736f-95d7-36ae8e298e4a","timestamp":"2026-07-31T10:00:00.000Z","cwd":"/tmp/demo"}
{"type":"message","id":"a1b2c3d4","parentId":null,"timestamp":"2026-07-31T10:00:01.000Z","message":{"role":"assistant","model":"deepseek-v4-flash","usage":{"input":100,"output":20,"cacheRead":50,"cacheWrite":0,"totalTokens":170}}}
{"type":"message","id":"b2c3d4e5","parentId":"a1b2c3d4","timestamp":"2026-07-31T10:00:02.000Z","message":{"role":"toolResult","toolCallId":"call_1","toolName":"bash","usage":{"input":5,"output":3,"cacheRead":0,"cacheWrite":0,"totalTokens":8}}}
{"type":"compaction","id":"c3d4e5f6","parentId":"b2c3d4e5","timestamp":"2026-07-31T10:00:03.000Z","summary":"...","usage":{"input":30,"output":10,"cacheRead":0,"cacheWrite":0,"totalTokens":40}}
{"type":"message","id":"d4e5f6g7","parentId":"c3d4e5f6","timestamp":"2026-07-31T10:00:04.000Z","message":{"role":"user","content":"next"}}
{"type":"message","id":"e5f6g7h8","parentId":"d4e5f6g7","timestamp":"2026-07-31T10:00:05.000Z","message":{"role":"assistant","model":"deepseek-v4-flash","usage":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"totalTokens":0}}}
`
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	ev, off, lastModel, err := ParsePiUsageFile(p, 0, "")
	if err != nil {
		t.Fatal(err)
	}
	// assistant + toolResult + compaction = 3; zero-usage and user lines skipped.
	if len(ev) != 3 {
		t.Fatalf("want 3 events, got %d: %+v", len(ev), ev)
	}
	if ev[0].Agent != "pi" || ev[0].Model != "deepseek-v4-flash" || ev[0].InputTokens != 100 || ev[0].OutputTokens != 20 || ev[0].CacheHitTokens != 50 {
		t.Fatalf("ev[0]=%+v", ev[0])
	}
	// toolResult inherits model from the previous assistant.
	if ev[1].Model != "deepseek-v4-flash" || ev[1].InputTokens != 5 {
		t.Fatalf("ev[1]=%+v", ev[1])
	}
	if ev[2].InputTokens != 30 || ev[2].OutputTokens != 10 {
		t.Fatalf("ev[2]=%+v", ev[2])
	}
	// SessionID from the file-name uuid (offset-independent).
	if ev[0].SessionID != "019fb7a3-1931-736f-95d7-36ae8e298e4a" {
		t.Fatalf("sessionID=%s", ev[0].SessionID)
	}
	wantKey := "pi:" + filepath.Base(p) + ":a1b2c3d4"
	if ev[0].DedupeKey != wantKey {
		t.Fatalf("dedupeKey=%s want %s", ev[0].DedupeKey, wantKey)
	}
	if lastModel != "deepseek-v4-flash" {
		t.Fatalf("lastModel=%s", lastModel)
	}

	// Incremental read at the same offset emits nothing.
	ev2, _, _, err := ParsePiUsageFile(p, off, lastModel)
	if err != nil {
		t.Fatal(err)
	}
	if len(ev2) != 0 {
		t.Fatalf("want 0 incremental events, got %d", len(ev2))
	}

	// Append a new assistant line: incremental read picks it up only.
	extra := `{"type":"message","id":"f6g7h8i9","parentId":"e5f6g7h8","timestamp":"2026-07-31T10:00:06.000Z","message":{"role":"assistant","model":"deepseek-v4-flash","usage":{"input":7,"output":2,"cacheRead":0,"cacheWrite":0,"totalTokens":9}}}
`
	f, err := os.OpenFile(p, os.O_APPEND|os.O_WRONLY, 0)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := f.WriteString(extra); err != nil {
		t.Fatal(err)
	}
	f.Close()
	ev3, _, _, err := ParsePiUsageFile(p, off, lastModel)
	if err != nil {
		t.Fatal(err)
	}
	if len(ev3) != 1 || ev3[0].InputTokens != 7 {
		t.Fatalf("want 1 appended event, got %d: %+v", len(ev3), ev3)
	}

	// Oversized offset restarts from 0 (truncated/replaced file recovery).
	ev4, off4, _, err := ParsePiUsageFile(p, off+100000, "")
	if err != nil {
		t.Fatal(err)
	}
	if off4 == 0 || len(ev4) != 4 {
		t.Fatalf("oversized offset should restart from 0: off=%d events=%d", off4, len(ev4))
	}
}
