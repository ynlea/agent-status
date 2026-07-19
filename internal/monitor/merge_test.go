package monitor

import (
	"testing"

	"github.com/ynlea/agent-status/pkg/apitypes"
)

func TestMergeCodexSessionsPrefersAppWorking(t *testing.T) {
	file := []apitypes.Session{{
		Agent: "codex", SessionID: "s1", DisplayName: "demo", State: apitypes.StateDone, Message: "task_complete",
	}}
	app := []apitypes.Session{{
		Agent: "codex", SessionID: "s1", DisplayName: "s1", State: apitypes.StateWorking, Message: "active", Source: "codex-app-server",
	}}
	file[0].Source = "codex-file"
	out := MergeCodexSessions(app, file)
	if len(out) != 1 {
		t.Fatalf("len=%d", len(out))
	}
	if out[0].State != apitypes.StateWorking {
		t.Fatalf("state=%s", out[0].State)
	}
	if out[0].DisplayName != "demo" {
		t.Fatalf("display=%s want demo from file", out[0].DisplayName)
	}
	if out[0].Source != "codex-app-server" {
		t.Fatalf("source=%s", out[0].Source)
	}
}

func TestMapThreadStatus(t *testing.T) {
	st, msg, live := mapThreadStatus([]byte(`{"type":"notLoaded"}`))
	if live {
		t.Fatal("notLoaded should not be live")
	}
	_ = st
	_ = msg
	st, msg, live = mapThreadStatus([]byte(`{"type":"active","activeFlags":["waitingOnApproval"]}`))
	if !live || st != apitypes.StateConfirm || msg != "waitingOnApproval" {
		t.Fatalf("got %v %q live=%v", st, msg, live)
	}
	st, _, live = mapThreadStatus([]byte(`{"type":"active","activeFlags":[]}`))
	if !live || st != apitypes.StateWorking {
		t.Fatalf("active -> working, got %v live=%v", st, live)
	}
}

func TestAppServerSnapshotSignatureIsStable(t *testing.T) {
	src := NewAppServerSource(nil, AppServerOptions{})
	src.sessions["thread-b"] = apitypes.Session{State: apitypes.StateWorking, Message: "active"}
	src.sessions["thread-a"] = apitypes.Session{State: apitypes.StateDone, Message: "turn_completed"}

	want := src.snapshotSignature()
	for range 100 {
		if got := src.snapshotSignature(); got != want {
			t.Fatalf("signature changed without a session change: got %q want %q", got, want)
		}
	}
}

func TestAppServerClearSessionsDropsRestartState(t *testing.T) {
	src := NewAppServerSource(nil, AppServerOptions{})
	src.sessions["thread-a"] = apitypes.Session{SessionID: "thread-a", State: apitypes.StateWorking}

	if !src.clearSessions() {
		t.Fatal("expected sessions to be cleared")
	}
	if got := src.Snapshot(); len(got) != 0 {
		t.Fatalf("stale sessions remained after restart cleanup: %v", got)
	}
	if src.clearSessions() {
		t.Fatal("empty session cache should not report a change")
	}
}
