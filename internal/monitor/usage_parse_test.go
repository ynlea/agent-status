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
	ev, off, lastModel, err := ParseCodexUsageFile(p, 0, "")
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

	// Append another token_count without a new turn_context; incremental parse
	// must keep model via startModel / prefix recovery.
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

	ev2, _, last2, err := ParseCodexUsageFile(p, off, lastModel)
	if err != nil {
		t.Fatal(err)
	}
	if len(ev2) != 1 || ev2[0].Model != "gpt-5.2" {
		t.Fatalf("incremental with startModel: %+v last=%s", ev2, last2)
	}

	// Without startModel, mid-file parse should recover model from prefix.
	ev3, _, last3, err := ParseCodexUsageFile(p, off, "")
	if err != nil {
		t.Fatal(err)
	}
	if len(ev3) != 1 || ev3[0].Model != "gpt-5.2" {
		t.Fatalf("incremental with prefix recovery: %+v last=%s", ev3, last3)
	}
}
