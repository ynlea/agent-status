package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"

	"github.com/ynlea/agent-status/internal/monitor"
	"github.com/ynlea/agent-status/pkg/apitypes"
)

type sessionSnap struct {
	Agent       string
	SessionID   string
	DisplayName string
	State       apitypes.SessionState
	Message     string
	Source      string
}

func sessionKey(s apitypes.Session) string {
	return s.Agent + "|" + s.SessionID
}

func main() {
	logger := slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))

	if len(os.Args) >= 2 && os.Args[1] == "claude-hook" {
		os.Args = append([]string{os.Args[0]}, os.Args[2:]...)
		if err := runClaudeHook(logger); err != nil {
			logger.Error("Claude Hook 处理失败", "错误", err)
			os.Exit(1)
		}
		return
	}

	cfgPath := flag.String("config", envOr("AGENT_STATUS_MONITOR_CONFIG", "monitor.json"), "config path")
	printOnly := flag.Bool("print-sessions", false, "scan once and print sessions JSON, no report")
	once := flag.Bool("once", false, "report once and exit")
	initLocal := flag.Bool("init", false, "initialize local integrations")
	initClaude := flag.Bool("claude", false, "configure Claude Code Hooks; requires --init")
	claudeSettings := flag.String("claude-settings", defaultClaudeSettingsPath(), "Claude Code settings.json path")
	flag.Parse()
	if *initLocal || *initClaude {
		if !*initLocal || !*initClaude {
			logger.Error("初始化参数不完整，请使用 --init --claude")
			os.Exit(2)
		}
		executable, err := resolveHookExecutable()
		if err != nil {
			logger.Error("无法确定 Claude Hook 调用的监控端二进制", "错误", err)
			os.Exit(2)
		}
		result, err := configureClaudeHooks(*claudeSettings, executable, *cfgPath)
		if err != nil {
			logger.Error("配置 Claude Code Hooks 失败", "错误", err)
			os.Exit(1)
		}
		logger.Info("Claude Code Hooks 配置完成",
			"设置文件", result.SettingsPath,
			"钩子命令", result.Command,
			"新增事件数", result.Added,
			"更新事件数", result.Updated,
			"备份文件", result.BackupPath,
		)
		return
	}

	cfg, err := monitor.LoadConfig(*cfgPath)
	if err != nil {
		logger.Error("加载监控配置失败", "错误", err, "路径", *cfgPath)
		os.Exit(2)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	var fileSrc *monitor.CodexFileSource
	if cfg.FileWatchEnabled() {
		fileSrc = monitor.NewCodexFileSource(cfg.CodexSessionsDir, logger, monitor.CodexFileWatchOptions{})
		if err := fileSrc.Start(ctx); err != nil {
			logger.Warn("Codex 会话文件监听启动失败，将使用定时扫描", "错误", err)
			fileSrc = nil
		} else {
			defer fileSrc.Stop()
		}
	}

	var appSrc *monitor.AppServerSource
	if cfg.AppServerEnabled() {
		appSrc = monitor.NewAppServerSource(logger, monitor.AppServerOptions{
			SandboxMode: cfg.CodexSandboxMode,
		})
		if err := appSrc.Start(ctx); err != nil {
			logger.Warn("Codex app-server 启动调用失败，将使用文件扫描并继续重试", "错误", err)
			// keep appSrc for supervise retries if Start returned nil with background supervise
		}
		defer appSrc.Stop()
	}

	if *printOnly {
		// wait a bit for app-server first poll when enabled
		if appSrc != nil {
			time.Sleep(500 * time.Millisecond)
		}
		sessions, err := collect(cfg, appSrc, fileSrc)
		if err != nil {
			logger.Error("采集会话状态失败", "错误", err)
			os.Exit(1)
		}
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		_ = enc.Encode(sessions)
		return
	}

	rep := monitor.NewReporter(cfg)
	prev := map[string]sessionSnap{}
	var reportMu sync.Mutex

	doReport := func(reason string) {
		reportMu.Lock()
		defer reportMu.Unlock()
		if err := reportOnce(logger, cfg, rep, prev, appSrc, fileSrc); err != nil {
			logger.Warn("上报会话状态失败", "原因", reason, "错误", err)
		}
	}

	if *once {
		doReport("once")
		if cfg.UsageScanEnabled() {
			us := monitor.NewUsageSyncer(cfg, rep, logger)
			if err := us.SyncOnce(); err != nil {
				logger.Warn("用量单次同步失败", "错误", err)
			}
		}
		return
	}

	logger.Info("监控端已启动",
		"服务地址", cfg.ServerURL,
		"机器名称", cfg.MachineName,
		"启用 Codex app-server", cfg.AppServerEnabled(),
		"启用 Codex 文件监听", fileSrc != nil && fileSrc.Ready(),
		"Codex 沙箱模式", emptyAs(cfg.CodexSandboxMode, "Codex 默认值"),
		"启用文件扫描兜底", true,
		"定时上报秒数", cfg.ReportIntervalSec,
		"启用用量采集", cfg.UsageScanEnabled(),
		"用量扫描秒数", cfg.UsageIntervalSec,
	)

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)

	if cfg.UsageScanEnabled() {
		us := monitor.NewUsageSyncer(cfg, rep, logger)
		go us.RunLoop(ctx.Done())
	}

	ticker := time.NewTicker(time.Duration(cfg.ReportIntervalSec) * time.Second)
	defer ticker.Stop()

	// initial + event-driven + periodic fallback
	doReport("startup")

	changes := make(chan struct{}, 1)
	forwardChanges := func(source <-chan struct{}) {
		if source == nil {
			return
		}
		go func() {
			for {
				select {
				case <-ctx.Done():
					return
				case <-source:
					select {
					case changes <- struct{}{}:
					default:
					}
				}
			}
		}()
	}
	if appSrc != nil {
		forwardChanges(appSrc.Changes())
	}
	if fileSrc != nil {
		forwardChanges(fileSrc.Changes())
	}

	for {
		select {
		case <-stop:
			logger.Info("监控端已停止")
			return
		case <-changes:
			// coalesce bursty app-server events
			time.Sleep(150 * time.Millisecond)
			// drain
			for {
				select {
				case <-changes:
					continue
				default:
				}
				break
			}
			doReport("实时事件")
		case <-ticker.C:
			doReport("interval")
		}
	}
}

func collect(cfg *monitor.Config, appSrc *monitor.AppServerSource, fileSrc *monitor.CodexFileSource) ([]apitypes.Session, error) {
	var fileCodex []apitypes.Session
	if fileSrc != nil && fileSrc.Ready() {
		fileCodex = fileSrc.Snapshot()
	} else {
		var err error
		fileCodex, err = monitor.ScanCodex(cfg.CodexSessionsDir)
		if err != nil {
			return nil, err
		}
	}
	for i := range fileCodex {
		if fileCodex[i].Source == "" {
			fileCodex[i].Source = "codex-file"
		}
	}
	var codex []apitypes.Session
	if appSrc != nil && appSrc.Ready() {
		app := appSrc.Snapshot()
		for i := range app {
			if app[i].Source == "" {
				app[i].Source = "codex-app-server"
			}
		}
		codex = monitor.MergeCodexSessions(app, fileCodex)
	} else {
		codex = fileCodex
	}

	sessions := make([]apitypes.Session, 0, len(codex)+8)
	sessions = append(sessions, codex...)
	cs, err := monitor.LoadClaudeState(cfg.StateFile)
	if err != nil {
		return nil, err
	}
	for _, s := range cs.List() {
		if s.Source == "" {
			s.Source = "claude-hook"
		}
		sessions = append(sessions, s)
	}
	return sessions, nil
}

func reportOnce(logger *slog.Logger, cfg *monitor.Config, rep *monitor.Reporter, prev map[string]sessionSnap, appSrc *monitor.AppServerSource, fileSrc *monitor.CodexFileSource) error {
	sessions, err := collect(cfg, appSrc, fileSrc)
	if err != nil {
		return err
	}
	if err := rep.Report(sessions); err != nil {
		return err
	}
	logSessionDiffs(logger, prev, sessions)
	return nil
}

func logSessionDiffs(logger *slog.Logger, prev map[string]sessionSnap, sessions []apitypes.Session) {
	curr := make(map[string]sessionSnap, len(sessions))
	sourceCount := map[string]int{}
	for _, s := range sessions {
		src := s.Source
		if src == "" {
			src = "unknown"
		}
		sourceCount[src]++
		curr[sessionKey(s)] = sessionSnap{
			Agent:       s.Agent,
			SessionID:   s.SessionID,
			DisplayName: s.DisplayName,
			State:       s.State,
			Message:     s.Message,
			Source:      src,
		}
	}

	if len(prev) == 0 {
		for k, v := range curr {
			prev[k] = v
		}
		logger.Info("会话基线已建立",
			"会话数", len(curr),
			"Codex app-server", sourceCount["codex-app-server"],
			"Codex 文件扫描", sourceCount["codex-file"],
			"Claude Hook", sourceCount["claude-hook"],
		)
		return
	}

	for k, now := range curr {
		old, ok := prev[k]
		if !ok {
			logger.Info("检测到新增会话",
				"来源", now.Source,
				"代理", now.Agent,
				"会话标识", now.SessionID,
				"显示名称", now.DisplayName,
				"状态", now.State,
				"说明", now.Message,
			)
			continue
		}
		if old.State != now.State || old.DisplayName != now.DisplayName || old.Message != now.Message || old.Source != now.Source {
			logger.Info("会话状态已变化",
				"来源", now.Source,
				"代理", now.Agent,
				"会话标识", now.SessionID,
				"显示名称", now.DisplayName,
				"原状态", old.State,
				"新状态", now.State,
				"原来源", old.Source,
				"说明", now.Message,
			)
		}
	}
	for k, old := range prev {
		if _, ok := curr[k]; !ok {
			logger.Info("会话已移除",
				"来源", old.Source,
				"代理", old.Agent,
				"会话标识", old.SessionID,
				"显示名称", old.DisplayName,
				"最后状态", old.State,
			)
		}
	}

	for k := range prev {
		delete(prev, k)
	}
	for k, v := range curr {
		prev[k] = v
	}
}

func runClaudeHook(logger *slog.Logger) error {
	cfgPath := flag.String("config", envOr("AGENT_STATUS_MONITOR_CONFIG", "monitor.json"), "config path")
	flag.Parse()

	statePath := ""
	if cfg, err := monitor.LoadConfig(*cfgPath); err == nil {
		statePath = cfg.StateFile
	} else {
		home, _ := os.UserHomeDir()
		statePath = home + "/.agent-status/claude-sessions.json"
		logger.Debug("未加载监控配置，使用默认 Claude 状态路径", "错误", err)
	}

	var raw map[string]interface{}
	if err := json.NewDecoder(os.Stdin).Decode(&raw); err != nil {
		return fmt.Errorf("stdin json: %w", err)
	}
	ev := monitor.HookEventFromMap(raw)
	cs, err := monitor.LoadClaudeState(statePath)
	if err != nil {
		return err
	}
	sess, err := cs.ApplyHookEvent(ev)
	if err != nil {
		return err
	}
	if cfg, err := monitor.LoadConfig(*cfgPath); err == nil {
		rep := monitor.NewReporter(cfg)
		sessions, _ := collect(cfg, nil, nil)
		if err := rep.Report(sessions); err != nil {
			logger.Warn("Claude Hook 上报失败", "错误", err)
		} else {
			logger.Info("Claude Hook 已上报",
				"来源", "claude-hook",
				"代理", sess.Agent,
				"会话标识", sess.SessionID,
				"显示名称", sess.DisplayName,
				"状态", sess.State,
				"说明", sess.Message,
			)
		}
	}
	return nil
}

func envOr(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func emptyAs(v, def string) string {
	if v == "" {
		return def
	}
	return v
}
