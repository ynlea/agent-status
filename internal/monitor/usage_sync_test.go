package monitor

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"
)

func TestUsageSyncerSkipsOpenWhenUnchanged(t *testing.T) {
	root := t.TempDir()
	projects := filepath.Join(root, "projects", "p1")
	if err := os.MkdirAll(projects, 0o755); err != nil {
		t.Fatal(err)
	}
	session := filepath.Join(projects, "sess.jsonl")
	line := `{"type":"assistant","timestamp":"2026-07-19T10:00:01Z","sessionId":"s1","message":{"id":"msg_1","role":"assistant","model":"claude-sonnet-4-5","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":1}}}` + "\n"
	if err := os.WriteFile(session, []byte(line), 0o644); err != nil {
		t.Fatal(err)
	}

	var reports atomic.Int32
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		reports.Add(1)
		w.WriteHeader(http.StatusOK)
	}))
	defer ts.Close()

	cfg := &Config{
		ServerURL:         ts.URL,
		Key:               "k",
		MachineID:         "m",
		MachineName:       "m",
		ClaudeProjectsDir: filepath.Join(root, "projects"),
		CodexSessionsDir:  filepath.Join(root, "codex-empty"),
		UsageStateFile:    filepath.Join(root, "cursors.json"),
		UsageIntervalSec:  60,
		UsageDiscoverSec:  600,
	}
	us := NewUsageSyncer(cfg, NewReporter(cfg), nil)
	if err := us.SyncOnce(); err != nil {
		t.Fatal(err)
	}
	if reports.Load() == 0 {
		t.Fatal("expected first sync to report usage")
	}
	first := reports.Load()

	if err := us.SyncOnce(); err != nil {
		t.Fatal(err)
	}
	if reports.Load() != first {
		t.Fatalf("unchanged tick should not report again: first=%d now=%d", first, reports.Load())
	}

	f, err := os.OpenFile(session, os.O_APPEND|os.O_WRONLY, 0)
	if err != nil {
		t.Fatal(err)
	}
	line2 := `{"type":"assistant","timestamp":"2026-07-19T10:00:02Z","sessionId":"s1","message":{"id":"msg_2","role":"assistant","model":"claude-sonnet-4-5","usage":{"input_tokens":3,"output_tokens":2,"cache_read_input_tokens":0}}}` + "\n"
	if _, err := f.WriteString(line2); err != nil {
		t.Fatal(err)
	}
	_ = f.Close()

	if err := us.SyncOnce(); err != nil {
		t.Fatal(err)
	}
	if reports.Load() <= first {
		t.Fatal("appended usage should report without rediscover")
	}
}

func TestUsageSyncerDiscoverCadence(t *testing.T) {
	root := t.TempDir()
	projects := filepath.Join(root, "projects", "p1")
	if err := os.MkdirAll(projects, 0o755); err != nil {
		t.Fatal(err)
	}
	cfg := &Config{
		ServerURL:         "http://127.0.0.1:9",
		Key:               "k",
		MachineID:         "m",
		MachineName:       "m",
		ClaudeProjectsDir: filepath.Join(root, "projects"),
		CodexSessionsDir:  filepath.Join(root, "codex-empty"),
		UsageStateFile:    filepath.Join(root, "cursors.json"),
		UsageIntervalSec:  60,
		UsageDiscoverSec:  3600,
	}
	us := NewUsageSyncer(cfg, NewReporter(cfg), nil)
	if err := us.SyncOnce(); err != nil {
		t.Fatal(err)
	}

	us.mu.Lock()
	us.state.LastDiscoverUnix = time.Now().Unix()
	us.state.BackfillDone = true
	us.mu.Unlock()

	newFile := filepath.Join(projects, "late.jsonl")
	if err := os.WriteFile(newFile, []byte("{}\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := us.SyncOnce(); err != nil {
		t.Fatal(err)
	}
	us.mu.Lock()
	_, seen := us.state.Files[newFile]
	us.mu.Unlock()
	if seen {
		t.Fatal("new file should wait for discover cadence")
	}

	us.mu.Lock()
	us.state.LastDiscoverUnix = time.Now().Add(-2 * time.Hour).Unix()
	us.mu.Unlock()
	if err := us.SyncOnce(); err != nil {
		t.Fatal(err)
	}
	us.mu.Lock()
	_, seen = us.state.Files[newFile]
	us.mu.Unlock()
	if !seen {
		t.Fatal("discover cadence elapsed; new file should be registered")
	}

	raw, err := os.ReadFile(cfg.UsageStateFile)
	if err != nil {
		t.Fatal(err)
	}
	var st usageState
	if err := json.Unmarshal(raw, &st); err != nil {
		t.Fatal(err)
	}
}
