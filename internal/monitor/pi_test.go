package monitor

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/ynlea/agent-status/pkg/apitypes"
)

// piSessionContent builds a minimal pi session file with a controllable last
// activity time so state-threshold tests stay deterministic.
func piSessionContent(cwd, sid, name, userMsg, assistantText string, lastActivity time.Time) string {
	ts := func(t time.Time) string { return t.UTC().Format("2006-01-02T15:04:05.000Z") }
	var b strings.Builder
	fmt.Fprintf(&b, `{"type":"session","version":3,"id":%q,"timestamp":%q,"cwd":%q}`+"\n",
		sid, ts(lastActivity.Add(-time.Minute)), cwd)
	if name != "" {
		fmt.Fprintf(&b, `{"type":"session_info","id":"si1","parentId":null,"timestamp":%q,"name":%q}`+"\n",
			ts(lastActivity.Add(-30*time.Second)), name)
	}
	fmt.Fprintf(&b, `{"type":"message","id":"m1","parentId":null,"timestamp":%q,"message":{"role":"user","content":%q}}`+"\n",
		ts(lastActivity.Add(-20*time.Second)), userMsg)
	if assistantText != "" {
		fmt.Fprintf(&b, `{"type":"message","id":"m2","parentId":"m1","timestamp":%q,"message":{"role":"assistant","content":[{"type":"text","text":%q},{"type":"thinking","thinking":"hidden"}],"model":"deepseek-v4-flash"}}`+"\n",
			ts(lastActivity), assistantText)
	}
	return b.String()
}

func writePiSessionFile(t *testing.T, dir, name, content string) string {
	t.Helper()
	p := filepath.Join(dir, name)
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

func TestScanPiTitlePriorityAndMeta(t *testing.T) {
	dir := t.TempDir()
	now := time.Now().UTC()

	// session_info.name wins over the first-user summary.
	writePiSessionFile(t, dir, "2026-07-31T10-00-00-000Z_aaa11111-0000-0000-0000-000000000001.jsonl",
		piSessionContent("/tmp/demo", "aaa11111-0000-0000-0000-000000000001", "重构登录模块",
			"帮我重构登录模块", "好的,开始重构。", now.Add(-2*time.Minute)))
	// No name: falls back to first-user summary.
	writePiSessionFile(t, dir, "2026-07-31T10-00-00-000Z_bbb22222-0000-0000-0000-000000000002.jsonl",
		piSessionContent("/tmp/other", "bbb22222-0000-0000-0000-000000000002", "",
			"这个任务怎么做的", "第一步……", now.Add(-2*time.Minute)))

	sessions, err := ScanPi(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(sessions) != 2 {
		t.Fatalf("want 2 sessions, got %d", len(sessions))
	}
	byID := map[string]apitypes.Session{}
	for _, s := range sessions {
		byID[s.SessionID] = s
	}
	s1 := byID["aaa11111-0000-0000-0000-000000000001"]
	if s1.DisplayName != "重构登录模块" {
		t.Fatalf("named session display=%q", s1.DisplayName)
	}
	if s1.Cwd != "/tmp/demo" {
		t.Fatalf("cwd=%q", s1.Cwd)
	}
	if s1.LastAssistantMessage != "好的,开始重构。" {
		t.Fatalf("lastAssistant=%q (thinking block must be excluded)", s1.LastAssistantMessage)
	}
	if s1.State != apitypes.StateWorking {
		t.Fatalf("state=%s want working (2min ago)", s1.State)
	}
	s2 := byID["bbb22222-0000-0000-0000-000000000002"]
	if s2.DisplayName != "这个任务怎么做的" {
		t.Fatalf("summarized session display=%q", s2.DisplayName)
	}
	if s2.Source != "pi-file" {
		t.Fatalf("source=%q", s2.Source)
	}
}

func TestScanPiStateThresholds(t *testing.T) {
	dir := t.TempDir()
	now := time.Now().UTC()

	// 1 minute ago → working; 10 minutes ago → idle.
	writePiSessionFile(t, dir, "w.jsonl",
		piSessionContent("/tmp/a", "w-session", "", "task a", "done a", now.Add(-time.Minute)))
	writePiSessionFile(t, dir, "i.jsonl",
		piSessionContent("/tmp/b", "i-session", "", "task b", "done b", now.Add(-10*time.Minute)))

	sessions, err := ScanPi(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(sessions) != 2 {
		t.Fatalf("want 2 sessions, got %d", len(sessions))
	}
	byID := map[string]apitypes.Session{}
	for _, s := range sessions {
		byID[s.SessionID] = s
	}
	if s := byID["w-session"]; s.State != apitypes.StateWorking {
		t.Fatalf("recent session state=%s want working", s.State)
	}
	if s := byID["i-session"]; s.State != apitypes.StateIdle {
		t.Fatalf("stale session state=%s want idle", s.State)
	}
	if s := byID["i-session"]; s.Message != "" {
		t.Fatalf("idle session message should be empty, got %q", s.Message)
	}
}

func TestScanPiIdleDrop(t *testing.T) {
	dir := t.TempDir()
	now := time.Now().UTC()

	// Idle for >24h: session is dropped entirely (matches codex policy).
	writePiSessionFile(t, dir, "old.jsonl",
		piSessionContent("/tmp/old", "old-session", "", "old task", "done", now.Add(-25*time.Hour)))

	sessions, err := ScanPi(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(sessions) != 0 {
		t.Fatalf("want 0 sessions (idle>24h dropped), got %d", len(sessions))
	}
}

func TestScanPiSkipsNonSessionFiles(t *testing.T) {
	dir := t.TempDir()
	now := time.Now().UTC()
	writePiSessionFile(t, dir, "active.jsonl",
		piSessionContent("/tmp/x", "active-session", "", "hi", "yo", now.Add(-time.Minute)))
	// A non-jsonl file and a jsonl without a session header must be ignored.
	writePiSessionFile(t, dir, "notes.txt", "not jsonl")
	writePiSessionFile(t, dir, "broken.jsonl", `{"type":"custom","id":"x1"}`+"\n")

	sessions, err := ScanPi(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(sessions) != 1 || sessions[0].SessionID != "active-session" {
		t.Fatalf("want only the real session, got %d: %+v", len(sessions), sessions)
	}
}
