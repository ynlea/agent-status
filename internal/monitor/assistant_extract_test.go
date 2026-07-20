package monitor

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestLastAssistantFromTranscript(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "sess.jsonl")
	content := strings.Join([]string{
		`{"type":"user","message":{"role":"user","content":[{"type":"text","text":"hello"}]}}`,
		`{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"first reply"}]}}`,
		`{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"final agent answer\nline2"}]}}`,
	}, "\n") + "\n"
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	got := lastAssistantFromTranscript(path)
	want := "final agent answer\nline2"
	if got != want {
		t.Fatalf("got %q want %q", got, want)
	}
}

func TestExtractCodexAssistantText(t *testing.T) {
	payload := map[string]interface{}{
		"type": "message",
		"role": "assistant",
		"content": []interface{}{
			map[string]interface{}{"type": "output_text", "text": "已完成任务"},
		},
	}
	got := extractCodexAssistantText("response_item", "message", payload)
	if got != "已完成任务" {
		t.Fatalf("got %q", got)
	}
}
