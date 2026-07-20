package monitor

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/ynlea/agent-status/pkg/apitypes"
)

func TestCodexFileSourceUpdatesMultipleSessionsIndependently(t *testing.T) {
	root := t.TempDir()
	p1 := writeWatcherRollout(t, root, "rollout-session-one.jsonl", `{"type":"event_msg","payload":{"type":"user_message"}}`+"\n")
	p2 := writeWatcherRollout(t, root, "rollout-session-two.jsonl", `{"type":"event_msg","payload":{"type":"user_message"}}`+"\n")

	source := NewCodexFileSource(root, nil, CodexFileWatchOptions{})
	source.reloadFile(p1)
	source.reloadFile(p2)
	assertWatcherStates(t, source.Snapshot(), map[string]apitypes.SessionState{
		"session-one": apitypes.StateWorking,
		"session-two": apitypes.StateWorking,
	})

	appendWatcherLine(t, p1, `{"type":"event_msg","payload":{"type":"task_complete"}}`+"\n")
	source.updateFile(p1)
	assertWatcherStates(t, source.Snapshot(), map[string]apitypes.SessionState{
		"session-one": apitypes.StateDone,
		"session-two": apitypes.StateWorking,
	})
}

func TestCodexFileSourceKeepsPartialLineUntilComplete(t *testing.T) {
	root := t.TempDir()
	path := writeWatcherRollout(t, root, "rollout-session-partial.jsonl", `{"type":"event_msg","payload":{"type":"user_message"}}`)
	source := NewCodexFileSource(root, nil, CodexFileWatchOptions{})
	source.reloadFile(path)
	if got := source.Snapshot(); len(got) != 0 {
		t.Fatalf("partial JSONL line should not be parsed: %v", got)
	}

	appendWatcherLine(t, path, "\n")
	source.updateFile(path)
	assertWatcherStates(t, source.Snapshot(), map[string]apitypes.SessionState{
		"session-partial": apitypes.StateWorking,
	})
}

func TestCodexFileSourceRescanReconcilesWithoutFullReread(t *testing.T) {
	root := t.TempDir()
	path := writeWatcherRollout(t, root, "rollout-session-light.jsonl", `{"type":"event_msg","payload":{"type":"user_message"}}`+"\n")
	source := NewCodexFileSource(root, nil, CodexFileWatchOptions{})
	source.reloadFile(path)

	source.mu.RLock()
	offsetBefore := source.files[path].offset
	source.mu.RUnlock()
	if offsetBefore == 0 {
		t.Fatal("expected non-zero offset after initial load")
	}

	if err := source.rescan(); err != nil {
		t.Fatal(err)
	}
	source.mu.RLock()
	offsetAfter := source.files[path].offset
	source.mu.RUnlock()
	if offsetAfter != offsetBefore {
		t.Fatalf("unchanged file should keep offset: before=%d after=%d", offsetBefore, offsetAfter)
	}
	assertWatcherStates(t, source.Snapshot(), map[string]apitypes.SessionState{
		"session-light": apitypes.StateWorking,
	})

	appendWatcherLine(t, path, `{"type":"event_msg","payload":{"type":"task_complete"}}`+"\n")
	if err := source.rescan(); err != nil {
		t.Fatal(err)
	}
	assertWatcherStates(t, source.Snapshot(), map[string]apitypes.SessionState{
		"session-light": apitypes.StateDone,
	})
	source.mu.RLock()
	offsetGrew := source.files[path].offset
	source.mu.RUnlock()
	if offsetGrew <= offsetBefore {
		t.Fatalf("appended content should advance offset: before=%d after=%d", offsetBefore, offsetGrew)
	}
}

func TestCodexFileSourceWatchesNewDirectoriesAndFiles(t *testing.T) {
	root := t.TempDir()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	source := NewCodexFileSource(root, nil, CodexFileWatchOptions{RescanInterval: time.Hour})
	if err := source.Start(ctx); err != nil {
		t.Fatal(err)
	}
	defer source.Stop()

	dir := filepath.Join(root, "2026", "07", "18")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	writeWatcherRollout(t, dir, "rollout-session-a.jsonl", `{"type":"event_msg","payload":{"type":"user_message"}}`+"\n")
	writeWatcherRollout(t, dir, "rollout-session-b.jsonl", `{"type":"event_msg","payload":{"type":"task_complete"}}`+"\n")

	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		got := source.Snapshot()
		if len(got) == 2 {
			assertWatcherStates(t, got, map[string]apitypes.SessionState{
				"session-a": apitypes.StateWorking,
				"session-b": apitypes.StateDone,
			})
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatalf("new rollout files were not observed: %v", source.Snapshot())
}

func writeWatcherRollout(t *testing.T, dir, name, content string) string {
	t.Helper()
	path := filepath.Join(dir, name)
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func appendWatcherLine(t *testing.T, path, content string) {
	t.Helper()
	f, err := os.OpenFile(path, os.O_APPEND|os.O_WRONLY, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	if _, err := f.WriteString(content); err != nil {
		t.Fatal(err)
	}
}

func assertWatcherStates(t *testing.T, sessions []apitypes.Session, want map[string]apitypes.SessionState) {
	t.Helper()
	got := make(map[string]apitypes.SessionState, len(sessions))
	for _, session := range sessions {
		got[session.SessionID] = session.State
	}
	if len(got) != len(want) {
		t.Fatalf("session count=%d want=%d sessions=%v", len(got), len(want), sessions)
	}
	for id, state := range want {
		if got[id] != state {
			t.Fatalf("session %s state=%s want=%s", id, got[id], state)
		}
	}
}
