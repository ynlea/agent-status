package monitor

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// EnsureClaudeHooks re-injects agent-status Claude Code hooks into the live
// ~/.claude/settings.json. Safe to call repeatedly; no-op when already present.
//
// Why: cc-switch provider switch replaces the whole settings file, which drops
// hooks that only existed in the previous live file.
func EnsureClaudeHooks(monitorConfigPath string) error {
	if strings.TrimSpace(monitorConfigPath) == "" {
		return fmt.Errorf("monitor config path empty")
	}
	cfgPath, err := filepath.Abs(monitorConfigPath)
	if err != nil {
		return err
	}
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	if resolved, err := filepath.EvalSymlinks(exe); err == nil {
		exe = resolved
	}
	exe, err = filepath.Abs(exe)
	if err != nil {
		return err
	}
	// go run temp binaries cannot be used as stable hook targets.
	if strings.Contains(filepath.ToSlash(exe), "/go-build") {
		return fmt.Errorf("monitor binary is a go-build temp path; install a real binary first")
	}

	// hard cap so a stuck init cannot block the command pipeline forever
	cmd := exec.Command(exe, "--init", "--claude", "--config", cfgPath)
	done := make(chan error, 1)
	go func() {
		out, err := cmd.CombinedOutput()
		if err != nil {
			msg := strings.TrimSpace(string(out))
			if msg == "" {
				msg = err.Error()
			}
			if len(msg) > 300 {
				msg = msg[:300]
			}
			done <- fmt.Errorf("ensure claude hooks: %s", msg)
			return
		}
		done <- nil
	}()
	select {
	case err := <-done:
		return err
	case <-time.After(20 * time.Second):
		_ = cmd.Process.Kill()
		return fmt.Errorf("ensure claude hooks timed out")
	}
}
