package monitor

import (
	"os"
	"path/filepath"
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
	ev, _, err := ParseCodexUsageFile(p, 0)
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
}
