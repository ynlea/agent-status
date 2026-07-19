package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

var claudeHookEvents = []string{
	"SessionStart",
	"UserPromptSubmit",
	"PreToolUse",
	"PostToolUse",
	"PostToolUseFailure",
	"PermissionRequest",
	"Notification",
	"Stop",
	"StopFailure",
	"SubagentStop",
	"SessionEnd",
}

type claudeInitResult struct {
	SettingsPath string
	BackupPath   string
	Command      string
	Added        int
	Updated      int
}

func defaultClaudeSettingsPath() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return ".claude/settings.json"
	}
	return filepath.Join(home, ".claude", "settings.json")
}

func resolveHookExecutable() (string, error) {
	executable, err := os.Executable()
	if err != nil {
		return "", err
	}
	if resolved, err := filepath.EvalSymlinks(executable); err == nil {
		executable = resolved
	}
	executable, err = filepath.Abs(executable)
	if err != nil {
		return "", err
	}
	normalized := filepath.ToSlash(executable)
	if strings.Contains(normalized, "/go-build") {
		return "", fmt.Errorf("检测到 go run 的临时路径；请先构建 bin/agent-status-monitor，再运行 --init --claude")
	}
	info, err := os.Stat(executable)
	if err != nil {
		return "", err
	}
	if info.IsDir() || info.Mode()&0o111 == 0 {
		return "", fmt.Errorf("监控端二进制不可执行: %s", executable)
	}
	return executable, nil
}

func configureClaudeHooks(settingsPath, executable, monitorConfig string) (claudeInitResult, error) {
	settingsPath, err := filepath.Abs(settingsPath)
	if err != nil {
		return claudeInitResult{}, err
	}
	monitorConfig, err = filepath.Abs(monitorConfig)
	if err != nil {
		return claudeInitResult{}, err
	}
	command := shellQuote(executable) + " claude-hook --config " + shellQuote(monitorConfig)
	result := claudeInitResult{SettingsPath: settingsPath, Command: command}

	data, readErr := os.ReadFile(settingsPath)
	if readErr != nil && !os.IsNotExist(readErr) {
		return claudeInitResult{}, readErr
	}
	document := map[string]any{}
	if len(bytes.TrimSpace(data)) > 0 {
		if err := json.Unmarshal(data, &document); err != nil {
			return claudeInitResult{}, fmt.Errorf("解析 Claude 设置文件: %w", err)
		}
	}

	hooks, err := getHooks(document)
	if err != nil {
		return claudeInitResult{}, err
	}
	changed := false
	for _, event := range claudeHookEvents {
		added, updated, err := mergeClaudeHook(hooks, event, command)
		if err != nil {
			return claudeInitResult{}, err
		}
		result.Added += added
		result.Updated += updated
		changed = changed || added > 0 || updated > 0
	}
	if !changed {
		return result, nil
	}
	document["hooks"] = hooks
	encoded, err := json.MarshalIndent(document, "", "  ")
	if err != nil {
		return claudeInitResult{}, err
	}
	encoded = append(encoded, '\n')

	if len(data) > 0 {
		backupPath := settingsPath + ".agent-status.bak"
		if _, err := os.Stat(backupPath); os.IsNotExist(err) {
			if err := writePrivateFile(backupPath, data); err != nil {
				return claudeInitResult{}, fmt.Errorf("备份 Claude 设置文件: %w", err)
			}
		}
		result.BackupPath = backupPath
	}
	if err := writePrivateFile(settingsPath, encoded); err != nil {
		return claudeInitResult{}, err
	}
	return result, nil
}

func getHooks(document map[string]any) (map[string]any, error) {
	raw, exists := document["hooks"]
	if !exists || raw == nil {
		hooks := map[string]any{}
		document["hooks"] = hooks
		return hooks, nil
	}
	hooks, ok := raw.(map[string]any)
	if !ok {
		return nil, fmt.Errorf("Claude 设置中的 hooks 不是对象")
	}
	return hooks, nil
}

func mergeClaudeHook(hooks map[string]any, event, command string) (int, int, error) {
	raw, exists := hooks[event]
	if !exists || raw == nil {
		hooks[event] = []any{newClaudeHookGroup(command)}
		return 1, 0, nil
	}
	groups, ok := raw.([]any)
	if !ok {
		return 0, 0, fmt.Errorf("Claude Hook %s 不是数组", event)
	}
	found := false
	updated := false
	for _, rawGroup := range groups {
		group, ok := rawGroup.(map[string]any)
		if !ok {
			continue
		}
		rawHandlers, ok := group["hooks"].([]any)
		if !ok {
			continue
		}
		for _, rawHandler := range rawHandlers {
			handler, ok := rawHandler.(map[string]any)
			if !ok || handler["type"] != "command" {
				continue
			}
			current, _ := handler["command"].(string)
			if !isAgentStatusClaudeHook(current) {
				continue
			}
			found = true
			if current != command {
				handler["command"] = command
				updated = true
			}
			if async, _ := handler["async"].(bool); !async {
				handler["async"] = true
				updated = true
			}
		}
	}
	if found {
		if updated {
			return 0, 1, nil
		}
		return 0, 0, nil
	}
	hooks[event] = append(groups, newClaudeHookGroup(command))
	return 1, 0, nil
}

func newClaudeHookGroup(command string) map[string]any {
	return map[string]any{
		"hooks": []any{
			map[string]any{
				"type":    "command",
				"command": command,
				"async":   true,
			},
		},
	}
}

func isAgentStatusClaudeHook(command string) bool {
	return strings.Contains(command, "agent-status-monitor") && strings.Contains(command, "claude-hook")
}

func shellQuote(value string) string {
	return "'" + strings.ReplaceAll(value, "'", "'\"'\"'") + "'"
}

func writePrivateFile(path string, data []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(path), ".agent-status-*")
	if err != nil {
		return err
	}
	tmpPath := tmp.Name()
	defer os.Remove(tmpPath)
	if err := tmp.Chmod(0o600); err != nil {
		_ = tmp.Close()
		return err
	}
	if _, err := tmp.Write(data); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmpPath, path)
}
