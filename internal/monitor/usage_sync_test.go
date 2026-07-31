package monitor

import (
	"encoding/json"
	"github.com/ynlea/agent-status/pkg/apitypes"
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

func TestUsageSyncerRebindsOnServerURLChange(t *testing.T) {
	root := t.TempDir()
	projects := filepath.Join(root, "projects", "p1")
	if err := os.MkdirAll(projects, 0o755); err != nil {
		t.Fatal(err)
	}
	session := filepath.Join(projects, "sess.jsonl")
	line := `{"type":"assistant","timestamp":"2026-07-19T10:00:01Z","sessionId":"s1","message":{"id":"msg_rebind","role":"assistant","model":"claude-sonnet-4-5","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":1}}}` + "\n"
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
		t.Fatal("expected initial report")
	}
	first := reports.Load()

	// Simulate switching to a new empty server (same test server is fine; we care about re-upload).
	cfg.ServerURL = ts.URL + "/v2"
	us2 := NewUsageSyncer(cfg, NewReporter(cfg), nil)
	if err := us2.SyncOnce(); err != nil {
		t.Fatal(err)
	}
	if reports.Load() <= first {
		t.Fatalf("server_url change should force full re-upload: first=%d now=%d", first, reports.Load())
	}
	us2.mu.Lock()
	done := us2.state.BackfillDone
	bound := us2.state.ServerURL
	us2.mu.Unlock()
	if !done {
		t.Fatal("successful rebind sync should mark backfill done")
	}
	if bound != normalizeServerURL(cfg.ServerURL) {
		t.Fatalf("server_url not bound: got %q want %q", bound, normalizeServerURL(cfg.ServerURL))
	}
}

func TestUsageSyncerReportFailureKeepsBackfillOpen(t *testing.T) {
	root := t.TempDir()
	projects := filepath.Join(root, "projects", "p1")
	if err := os.MkdirAll(projects, 0o755); err != nil {
		t.Fatal(err)
	}
	session := filepath.Join(projects, "sess.jsonl")
	line := `{"type":"assistant","timestamp":"2026-07-19T10:00:01Z","sessionId":"s1","message":{"id":"msg_fail","role":"assistant","model":"claude-sonnet-4-5","usage":{"input_tokens":10,"output_tokens":5,"cache_read_input_tokens":1}}}` + "\n"
	if err := os.WriteFile(session, []byte(line), 0o644); err != nil {
		t.Fatal(err)
	}

	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "nope", http.StatusInternalServerError)
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
	if err := us.SyncOnce(); err == nil {
		t.Fatal("expected report failure")
	}
	us.mu.Lock()
	done := us.state.BackfillDone
	offset := us.state.Files[session].Offset
	us.mu.Unlock()
	if done {
		t.Fatal("failed report must not mark backfill_done")
	}
	if offset != 0 {
		t.Fatalf("failed report must not advance file cursor, offset=%d", offset)
	}
}

// TestUsageSyncerStartupDiscoversNewAgentDir ensures a fresh agent source
// (e.g. pi sessions) is discovered on the first tick after startup even when
// the persisted cursor state is fully caught up and the periodic discover
// interval has not elapsed yet.
func TestUsageSyncerStartupDiscoversNewAgentDir(t *testing.T) {
	root := t.TempDir()
	claudeDir := filepath.Join(root, "claude", "p1")
	piDir := filepath.Join(root, "pi")
	for _, d := range []string{claudeDir, piDir} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	known := filepath.Join(claudeDir, "known.jsonl")
	knownLine := `{"type":"assistant","timestamp":"2026-07-19T10:00:01Z","sessionId":"s1","message":{"id":"msg_1","role":"assistant","model":"claude-sonnet-4-5","usage":{"input_tokens":10,"output_tokens":5}}}` + "\n"
	if err := os.WriteFile(known, []byte(knownLine), 0o644); err != nil {
		t.Fatal(err)
	}
	// Pi session file unknown to the persisted cursor state.
	piFile := filepath.Join(piDir, "2026-07-31T10-00-00-000Z_019f0000-0000-0000-0000-000000000000.jsonl")
	piContent := `{"type":"session","id":"019f0000-0000-0000-0000-000000000000","cwd":"/tmp","timestamp":"2026-07-31T10:00:00.000Z"}` + "\n" +
		`{"type":"message","id":"a1b2c3d4","timestamp":"2026-07-31T10:00:01.000Z","message":{"role":"assistant","model":"deepseek-v4-flash","usage":{"input":100,"output":20}}}` + "\n"
	if err := os.WriteFile(piFile, []byte(piContent), 0o644); err != nil {
		t.Fatal(err)
	}

	var piEvents atomic.Int32
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/api/v1/usage/report" {
			var req apitypes.UsageReportRequest
			if json.NewDecoder(r.Body).Decode(&req) == nil {
				for _, ev := range req.Events {
					if ev.Agent == "pi" {
						piEvents.Add(1)
					}
				}
			}
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer ts.Close()

	// Persisted cursor: fully caught up, discover ran 1 minute ago (well
	// inside the 600s interval), no pi files tracked.
	state := usageState{
		ServerURL:        ts.URL,
		BackfillDone:     true,
		LastDiscoverUnix: time.Now().Add(-time.Minute).Unix(),
		Files: map[string]fileCursor{
			known: {Offset: int64(len(knownLine)), Size: int64(len(knownLine)), Kind: "claude"},
		},
	}
	statePath := filepath.Join(root, "cursors.json")
	raw, err := json.Marshal(state)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(statePath, raw, 0o600); err != nil {
		t.Fatal(err)
	}

	cfg := &Config{
		ServerURL:         ts.URL,
		Key:               "k",
		MachineID:         "m",
		MachineName:       "m",
		ClaudeProjectsDir: filepath.Join(root, "claude"),
		CodexSessionsDir:  filepath.Join(root, "codex-empty"),
		PiSessionsDir:     piDir,
		UsageStateFile:    statePath,
		UsageIntervalSec:  60,
		UsageDiscoverSec:  600,
	}
	us := NewUsageSyncer(cfg, NewReporter(cfg), nil)
	if err := us.SyncOnce(); err != nil {
		t.Fatal(err)
	}
	if piEvents.Load() == 0 {
		t.Fatal("expected startup tick to discover the new pi dir and report usage")
	}
}
