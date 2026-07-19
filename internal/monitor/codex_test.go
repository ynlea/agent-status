package monitor

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/ynlea/agent-status/pkg/apitypes"
)

func writeRollout(t *testing.T, dir, name, content string) string {
	t.Helper()
	path := filepath.Join(dir, name)
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestScanCodexWorkingFromTaskStarted(t *testing.T) {
	root := t.TempDir()
	dir := filepath.Join(root, "2026", "07", "18")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	now := time.Now().UTC().Format(time.RFC3339Nano)
	content := "" +
		`{"timestamp":"` + now + `","type":"event_msg","payload":{"type":"task_started"}}` + "\n" +
		`{"timestamp":"` + now + `","type":"turn_context","payload":{"cwd":"/home/u/projects/demo"}}` + "\n" +
		`{"timestamp":"` + now + `","type":"response_item","payload":{"type":"custom_tool_call","name":"shell"}}` + "\n"
	writeRollout(t, dir, "rollout-sess-working.jsonl", content)

	sessions, err := ScanCodex(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(sessions) != 1 {
		t.Fatalf("got %d", len(sessions))
	}
	if sessions[0].State != apitypes.StateWorking {
		t.Fatalf("state=%s want working", sessions[0].State)
	}
	if sessions[0].DisplayName != "demo" {
		t.Fatalf("display=%s", sessions[0].DisplayName)
	}
}

func TestScanCodexDoneFromTaskComplete(t *testing.T) {
	root := t.TempDir()
	dir := filepath.Join(root, "2026", "07", "18")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	now := time.Now().UTC().Format(time.RFC3339Nano)
	content := "" +
		`{"timestamp":"` + now + `","type":"event_msg","payload":{"type":"task_started"}}` + "\n" +
		`{"timestamp":"` + now + `","type":"event_msg","payload":{"type":"task_complete"}}` + "\n"
	// include approval_policy noise that old heuristic misread as confirm
	content += `{"timestamp":"` + now + `","type":"turn_context","payload":{"cwd":"/tmp/x","approval_policy":"never","permission_profile":{"type":"disabled"}}}` + "\n"
	writeRollout(t, dir, "rollout-sess-done.jsonl", content)

	sessions, err := ScanCodex(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(sessions) != 1 {
		t.Fatalf("got %d", len(sessions))
	}
	if sessions[0].State != apitypes.StateDone {
		t.Fatalf("state=%s want done (approval_policy must not force confirm)", sessions[0].State)
	}
}

func TestScanCodexDropsColdIdle(t *testing.T) {
	root := t.TempDir()
	dir := filepath.Join(root, "2026", "03", "01")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	path := writeRollout(t, dir, "rollout-old.jsonl",
		`{"timestamp":"2026-03-01T00:00:00Z","type":"event_msg","payload":{"type":"task_complete"}}`+"\n")
	old := time.Now().Add(-48 * time.Hour)
	if err := os.Chtimes(path, old, old); err != nil {
		t.Fatal(err)
	}
	sessions, err := ScanCodex(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(sessions) != 0 {
		t.Fatalf("expected cold idle dropped, got %v", sessions)
	}
}

func TestClaudeHookPermission(t *testing.T) {
	path := filepath.Join(t.TempDir(), "state.json")
	cs, err := LoadClaudeState(path)
	if err != nil {
		t.Fatal(err)
	}
	sess, err := cs.ApplyHookEvent(HookEvent{
		HookEventName: "PermissionRequest",
		SessionID:     "s1",
		Cwd:           "/tmp/work",
	})
	if err != nil {
		t.Fatal(err)
	}
	if sess.State != apitypes.StateConfirm {
		t.Fatalf("state=%s", sess.State)
	}
}

func TestClaudeHookSessionStartStaysIdleUntilPrompt(t *testing.T) {
	path := filepath.Join(t.TempDir(), "state.json")
	cs, err := LoadClaudeState(path)
	if err != nil {
		t.Fatal(err)
	}
	sess, err := cs.ApplyHookEvent(HookEvent{
		HookEventName: "SessionStart",
		SessionID:     "s1",
		Cwd:           "/tmp/work",
	})
	if err != nil {
		t.Fatal(err)
	}
	if sess.State != apitypes.StateIdle {
		t.Fatalf("SessionStart state=%s want idle", sess.State)
	}
	sess, err = cs.ApplyHookEvent(HookEvent{
		HookEventName: "UserPromptSubmit",
		SessionID:     "s1",
		Cwd:           "/tmp/work",
		UserPrompt:    "整理通知里的提示词和会话目录\n第二行",
	})
	if err != nil {
		t.Fatal(err)
	}
	if sess.State != apitypes.StateWorking {
		t.Fatalf("UserPromptSubmit state=%s want working", sess.State)
	}
	if sess.Message != "整理通知里的提示词和会话目录" {
		t.Fatalf("summary=%q", sess.Message)
	}
	sess, err = cs.ApplyHookEvent(HookEvent{
		HookEventName: "Stop",
		SessionID:     "s1",
		Cwd:           "/tmp/work",
	})
	if err != nil {
		t.Fatal(err)
	}
	if sess.State != apitypes.StateDone {
		t.Fatalf("Stop state=%s want done", sess.State)
	}
	if sess.Message != "整理通知里的提示词和会话目录" {
		t.Fatalf("Stop should keep summary, got %q", sess.Message)
	}
}

func TestClaudeIdleNotificationDoesNotOverwriteDone(t *testing.T) {
	path := filepath.Join(t.TempDir(), "state.json")
	cs, err := LoadClaudeState(path)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := cs.ApplyHookEvent(HookEvent{
		HookEventName: "UserPromptSubmit",
		SessionID:     "s-done",
		Cwd:           "/tmp/work",
		UserPrompt:    "修登录超时",
	}); err != nil {
		t.Fatal(err)
	}
	sess, err := cs.ApplyHookEvent(HookEvent{
		HookEventName: "Stop",
		SessionID:     "s-done",
		Cwd:           "/tmp/work",
	})
	if err != nil {
		t.Fatal(err)
	}
	if sess.State != apitypes.StateDone {
		t.Fatalf("after Stop state=%s", sess.State)
	}
	// Claude often fires Notification(idle_prompt) after a turn ends — must stay done.
	sess, err = cs.ApplyHookEvent(HookEvent{
		HookEventName:    "Notification",
		SessionID:        "s-done",
		Cwd:              "/tmp/work",
		NotificationType: "idle_prompt",
		Message:          "Claude is waiting for your input",
	})
	if err != nil {
		t.Fatal(err)
	}
	if sess.State != apitypes.StateDone {
		t.Fatalf("idle notification overwrote done → %s", sess.State)
	}
	if sess.Message != "修登录超时" {
		t.Fatalf("summary lost: %q", sess.Message)
	}
	// Real permission notifications still go confirm.
	sess, err = cs.ApplyHookEvent(HookEvent{
		HookEventName:    "Notification",
		SessionID:        "s-done",
		Cwd:              "/tmp/work",
		NotificationType: "permission_prompt",
	})
	if err != nil {
		t.Fatal(err)
	}
	if sess.State != apitypes.StateConfirm {
		t.Fatalf("permission notification state=%s want confirm", sess.State)
	}
}

func TestClaudePermissionThenToolRestoresWorking(t *testing.T) {
	path := filepath.Join(t.TempDir(), "state.json")
	cs, err := LoadClaudeState(path)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := cs.ApplyHookEvent(HookEvent{
		HookEventName: "UserPromptSubmit",
		SessionID:     "s-perm",
		Cwd:           "/tmp/work",
		UserPrompt:    "改代码",
	}); err != nil {
		t.Fatal(err)
	}
	sess, err := cs.ApplyHookEvent(HookEvent{
		HookEventName:  "PermissionRequest",
		SessionID:      "s-perm",
		Cwd:            "/tmp/work",
		PermissionMode: "default",
		ToolName:       "Bash",
	})
	if err != nil {
		t.Fatal(err)
	}
	if sess.State != apitypes.StateConfirm {
		t.Fatalf("PermissionRequest state=%s want confirm", sess.State)
	}
	// Auto-allow / user approve → tool starts → working again (not sticky 待确认).
	sess, err = cs.ApplyHookEvent(HookEvent{
		HookEventName: "PreToolUse",
		SessionID:     "s-perm",
		Cwd:           "/tmp/work",
		ToolName:      "Bash",
	})
	if err != nil {
		t.Fatal(err)
	}
	if sess.State != apitypes.StateWorking {
		t.Fatalf("PreToolUse state=%s want working", sess.State)
	}
	if sess.Message != "改代码" {
		t.Fatalf("summary lost: %q", sess.Message)
	}
}

func TestClaudeBypassPermissionStaysWorking(t *testing.T) {
	path := filepath.Join(t.TempDir(), "state.json")
	cs, err := LoadClaudeState(path)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := cs.ApplyHookEvent(HookEvent{
		HookEventName: "UserPromptSubmit",
		SessionID:     "s-bypass",
		Cwd:           "/tmp/work",
		UserPrompt:    "继续",
	}); err != nil {
		t.Fatal(err)
	}
	sess, err := cs.ApplyHookEvent(HookEvent{
		HookEventName:  "PermissionRequest",
		SessionID:      "s-bypass",
		Cwd:            "/tmp/work",
		PermissionMode: "bypassPermissions",
		ToolName:       "Bash",
	})
	if err != nil {
		t.Fatal(err)
	}
	if sess.State != apitypes.StateWorking {
		t.Fatalf("bypass PermissionRequest state=%s want working", sess.State)
	}
}

func TestClaudeCancelReasonGoesIdle(t *testing.T) {
	path := filepath.Join(t.TempDir(), "state.json")
	cs, err := LoadClaudeState(path)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := cs.ApplyHookEvent(HookEvent{
		HookEventName: "UserPromptSubmit",
		SessionID:     "s-cancel",
		Cwd:           "/tmp/work",
		UserPrompt:    "长任务",
	}); err != nil {
		t.Fatal(err)
	}
	sess, err := cs.ApplyHookEvent(HookEvent{
		HookEventName: "Stop",
		SessionID:     "s-cancel",
		Cwd:           "/tmp/work",
		Reason:        "user_interrupt",
	})
	if err != nil {
		t.Fatal(err)
	}
	if sess.State != apitypes.StateIdle {
		t.Fatalf("cancel Stop state=%s want idle", sess.State)
	}
}

func TestClaudeWorkingTimeoutClearsZombie(t *testing.T) {
	path := filepath.Join(t.TempDir(), "state.json")
	cs, err := LoadClaudeState(path)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := cs.ApplyHookEvent(HookEvent{
		HookEventName: "UserPromptSubmit",
		SessionID:     "s-zombie",
		Cwd:           "/tmp/work",
		UserPrompt:    "卡住了",
	}); err != nil {
		t.Fatal(err)
	}

	// Within 45m window: still working.
	s := cs.Sessions["s-zombie"]
	s.UpdatedAt = time.Now().UTC().Add(-20 * time.Minute)
	cs.Sessions["s-zombie"] = s
	_ = cs.saveLocked()
	list := cs.List()
	var found bool
	for _, item := range list {
		if item.SessionID == "s-zombie" {
			found = true
			if item.State != apitypes.StateWorking {
				t.Fatalf("20m working state=%s want working", item.State)
			}
		}
	}
	if !found {
		t.Fatal("expected working session still listed")
	}

	// Beyond 45m: zombie → idle.
	s = cs.Sessions["s-zombie"]
	s.State = apitypes.StateWorking
	s.UpdatedAt = time.Now().UTC().Add(-50 * time.Minute)
	cs.Sessions["s-zombie"] = s
	_ = cs.saveLocked()
	list = cs.List()
	found = false
	for _, item := range list {
		if item.SessionID == "s-zombie" {
			found = true
			if item.State != apitypes.StateIdle {
				t.Fatalf("zombie state=%s want idle", item.State)
			}
		}
	}
	if !found {
		t.Fatal("expected zombie session still listed as idle")
	}
}

func TestClaudeSubagentStopAndToolFailure(t *testing.T) {
	path := filepath.Join(t.TempDir(), "state.json")
	cs, err := LoadClaudeState(path)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := cs.ApplyHookEvent(HookEvent{
		HookEventName: "UserPromptSubmit",
		SessionID:     "s-sub",
		Cwd:           "/tmp/work",
		UserPrompt:    "子任务",
	}); err != nil {
		t.Fatal(err)
	}
	sess, err := cs.ApplyHookEvent(HookEvent{
		HookEventName: "PostToolUseFailure",
		SessionID:     "s-sub",
		Cwd:           "/tmp/work",
	})
	if err != nil {
		t.Fatal(err)
	}
	if sess.State != apitypes.StateWorking {
		t.Fatalf("PostToolUseFailure state=%s want working", sess.State)
	}
	sess, err = cs.ApplyHookEvent(HookEvent{
		HookEventName: "SubagentStop",
		SessionID:     "s-sub",
		Cwd:           "/tmp/work",
	})
	if err != nil {
		t.Fatal(err)
	}
	if sess.State != apitypes.StateDone {
		t.Fatalf("SubagentStop state=%s want done", sess.State)
	}
	sess, err = cs.ApplyHookEvent(HookEvent{
		HookEventName: "UserPromptSubmit",
		SessionID:     "s-sub-cancel",
		Cwd:           "/tmp/work",
		UserPrompt:    "取消子任务",
	})
	if err != nil {
		t.Fatal(err)
	}
	sess, err = cs.ApplyHookEvent(HookEvent{
		HookEventName: "SubagentStop",
		SessionID:     "s-sub-cancel",
		Cwd:           "/tmp/work",
		Reason:        "user_cancel",
	})
	if err != nil {
		t.Fatal(err)
	}
	if sess.State != apitypes.StateIdle {
		t.Fatalf("cancel SubagentStop state=%s want idle", sess.State)
	}
}

func TestClaudeStopNeverShowsStoppedLabel(t *testing.T) {
	path := filepath.Join(t.TempDir(), "state.json")
	cs, err := LoadClaudeState(path)
	if err != nil {
		t.Fatal(err)
	}
	// No prior summary: Stop must not leave message="stopped"
	sess, err := cs.ApplyHookEvent(HookEvent{
		HookEventName: "Stop",
		SessionID:     "s2",
		Cwd:           "/tmp/work",
	})
	if err != nil {
		t.Fatal(err)
	}
	if sess.State != apitypes.StateDone {
		t.Fatalf("state=%s", sess.State)
	}
	if sess.Message == "stopped" || sess.Message == "停止" {
		t.Fatalf("message should not be stopped label, got %q", sess.Message)
	}
}

func TestClaudeHookEventFromMapCamelCase(t *testing.T) {
	ev := HookEventFromMap(map[string]interface{}{
		"hookEventName": "UserPromptSubmit",
		"sessionId":     "s3",
		"cwd":           "/tmp/proj",
		"userPrompt":    "修登录超时",
	})
	if ev.HookEventName != "UserPromptSubmit" || ev.SessionID != "s3" {
		t.Fatalf("ev=%+v", ev)
	}
	if ev.promptText() != "修登录超时" {
		t.Fatalf("promptText=%q", ev.promptText())
	}
}

func TestClaudeTranscriptFallback(t *testing.T) {
	dir := t.TempDir()
	tr := filepath.Join(dir, "t.jsonl")
	content := `{"type":"last-prompt","lastPrompt":"编译一份release的apk","sessionId":"s4"}` + "\n"
	if err := os.WriteFile(tr, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "state.json")
	cs, err := LoadClaudeState(path)
	if err != nil {
		t.Fatal(err)
	}
	sess, err := cs.ApplyHookEvent(HookEvent{
		HookEventName:  "UserPromptSubmit",
		SessionID:      "s4",
		Cwd:            "/tmp/work",
		TranscriptPath: tr,
	})
	if err != nil {
		t.Fatal(err)
	}
	if sess.Message != "编译一份release的apk" {
		t.Fatalf("message=%q", sess.Message)
	}
}

func TestCodexUserMessageSummary(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "rollout-sess-summary.jsonl")
	now := time.Now().UTC().Format(time.RFC3339)
	content := `{"timestamp":"` + now + `","type":"event_msg","payload":{"type":"user_message","message":"修登录超时问题\n细节"}}` + "\n" +
		`{"timestamp":"` + now + `","type":"event_msg","payload":{"type":"task_complete"}}` + "\n"
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	sess, ok := parseCodexRollout(path)
	if !ok {
		t.Fatal("expected session")
	}
	if sess.State != apitypes.StateDone {
		t.Fatalf("state=%s want done", sess.State)
	}
	if sess.Message != "修登录超时问题" {
		t.Fatalf("message=%q want summary kept after complete", sess.Message)
	}
}
