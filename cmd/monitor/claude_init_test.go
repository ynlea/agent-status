package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestConfigureClaudeHooksMergesAndUpdates(t *testing.T) {
	dir := t.TempDir()
	settingsPath := filepath.Join(dir, "settings.json")
	configPath := filepath.Join(dir, "monitor.json")
	original := `{
  "permissions": {"allow": ["Bash(git status)"]},
  "hooks": {
    "Stop": [
      {"hooks": [{"type": "command", "command": "echo keep"}]},
      {"hooks": [{"type": "command", "command": "/old/agent-status-monitor claude-hook --config /old/monitor.json"}]}
    ]
  }
}`
	if err := os.WriteFile(settingsPath, []byte(original), 0o600); err != nil {
		t.Fatal(err)
	}

	result, err := configureClaudeHooks(settingsPath, "/opt/agent-status-monitor", configPath)
	if err != nil {
		t.Fatal(err)
	}
	if result.Added != len(claudeHookEvents)-1 || result.Updated != 1 {
		t.Fatalf("added=%d updated=%d", result.Added, result.Updated)
	}
	if result.BackupPath == "" {
		t.Fatal("expected settings backup")
	}
	if backup, err := os.ReadFile(result.BackupPath); err != nil || string(backup) != original {
		t.Fatalf("backup missing or changed: %v", err)
	}

	data, err := os.ReadFile(settingsPath)
	if err != nil {
		t.Fatal(err)
	}
	var document map[string]any
	if err := json.Unmarshal(data, &document); err != nil {
		t.Fatal(err)
	}
	permissions := document["permissions"].(map[string]any)
	if len(permissions["allow"].([]any)) != 1 {
		t.Fatalf("existing settings were not preserved: %v", permissions)
	}
	hooks := document["hooks"].(map[string]any)
	for _, event := range claudeHookEvents {
		if !hasAgentStatusHook(hooks[event]) {
			t.Fatalf("missing agent-status hook for %s", event)
		}
		if !hasAgentStatusAsync(hooks[event]) {
			t.Fatalf("agent-status hook for %s missing async=true", event)
		}
	}
	if !hasCommand(hooks["Stop"], "echo keep") {
		t.Fatal("existing Stop hook was removed")
	}
	if hasCommand(hooks["Stop"], "/old/agent-status-monitor claude-hook --config /old/monitor.json") {
		t.Fatal("old agent-status command was not updated")
	}

	again, err := configureClaudeHooks(settingsPath, "/opt/agent-status-monitor", configPath)
	if err != nil {
		t.Fatal(err)
	}
	if again.Added != 0 || again.Updated != 0 {
		t.Fatalf("second initialization should be idempotent: %+v", again)
	}
}

func TestShellQuote(t *testing.T) {
	got := shellQuote("/tmp/agent's monitor")
	if got != "'/tmp/agent'\"'\"'s monitor'" {
		t.Fatalf("quote=%q", got)
	}
}

func hasAgentStatusHook(raw any) bool {
	groups, _ := raw.([]any)
	for _, rawGroup := range groups {
		group, _ := rawGroup.(map[string]any)
		handlers, _ := group["hooks"].([]any)
		for _, rawHandler := range handlers {
			handler, _ := rawHandler.(map[string]any)
			command, _ := handler["command"].(string)
			if isAgentStatusClaudeHook(command) {
				return true
			}
		}
	}
	return false
}

func hasAgentStatusAsync(raw any) bool {
	groups, _ := raw.([]any)
	for _, rawGroup := range groups {
		group, _ := rawGroup.(map[string]any)
		handlers, _ := group["hooks"].([]any)
		for _, rawHandler := range handlers {
			handler, _ := rawHandler.(map[string]any)
			command, _ := handler["command"].(string)
			if !isAgentStatusClaudeHook(command) {
				continue
			}
			async, _ := handler["async"].(bool)
			return async
		}
	}
	return false
}

func hasCommand(raw any, want string) bool {
	groups, _ := raw.([]any)
	for _, rawGroup := range groups {
		group, _ := rawGroup.(map[string]any)
		handlers, _ := group["hooks"].([]any)
		for _, rawHandler := range handlers {
			handler, _ := rawHandler.(map[string]any)
			command, _ := handler["command"].(string)
			if command == want || strings.Contains(command, want) {
				return true
			}
		}
	}
	return false
}

func TestConfigureClaudeHooksSetsAsyncOnExisting(t *testing.T) {
	dir := t.TempDir()
	settingsPath := filepath.Join(dir, "settings.json")
	configPath := filepath.Join(dir, "monitor.json")
	original := `{
  "hooks": {
    "UserPromptSubmit": [
      {"hooks": [{"type": "command", "command": "/opt/agent-status-monitor claude-hook --config /x/monitor.json"}]}
    ]
  }
}`
	if err := os.WriteFile(settingsPath, []byte(original), 0o600); err != nil {
		t.Fatal(err)
	}
	result, err := configureClaudeHooks(settingsPath, "/opt/agent-status-monitor", configPath)
	if err != nil {
		t.Fatal(err)
	}
	if result.Updated < 1 {
		t.Fatalf("expected async upgrade update, got %+v", result)
	}
	data, err := os.ReadFile(settingsPath)
	if err != nil {
		t.Fatal(err)
	}
	var document map[string]any
	if err := json.Unmarshal(data, &document); err != nil {
		t.Fatal(err)
	}
	hooks := document["hooks"].(map[string]any)
	if !hasAgentStatusAsync(hooks["UserPromptSubmit"]) {
		t.Fatal("expected async=true after init")
	}
}
