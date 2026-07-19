package monitor

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/ynlea/agent-status/pkg/apitypes"
)

// AppServerOptions configures how the codex app-server process is launched.
type AppServerOptions struct {
	// SandboxMode is optional; when set, passed as -c sandbox_mode="<value>".
	// Empty = do not override Codex default (safer). Set per-host via config when AppArmor needs it.
	SandboxMode string
	// RestartDelay between process exits and relaunch.
	RestartDelay time.Duration
	// PollInterval for thread/list refresh while connected.
	PollInterval time.Duration
}

// AppServerSource talks to `codex app-server` over stdio JSON-RPC and keeps a
// live snapshot of thread statuses. Rollout file scanning remains the fallback.
type AppServerSource struct {
	opts   AppServerOptions
	logger *slog.Logger

	sessions map[string]apitypes.Session
	ready    atomic.Bool
	nextID   atomic.Int64

	cmd    *exec.Cmd
	stdin  io.WriteCloser
	cancel context.CancelFunc

	procMu  sync.Mutex
	sessMu  sync.RWMutex
	writeMu sync.Mutex
	waiters sync.Map // id string -> chan json.RawMessage

	// changes is a non-blocking notify channel for event-driven report.
	changes chan struct{}
}

func NewAppServerSource(logger *slog.Logger, opts AppServerOptions) *AppServerSource {
	if logger == nil {
		logger = slog.Default()
	}
	if opts.RestartDelay <= 0 {
		opts.RestartDelay = 3 * time.Second
	}
	if opts.PollInterval <= 0 {
		opts.PollInterval = 3 * time.Second
	}
	return &AppServerSource{
		opts:     opts,
		sessions: make(map[string]apitypes.Session),
		logger:   logger,
		changes:  make(chan struct{}, 1),
	}
}

// Changes returns a signal channel fired when live session state may have changed.
// Receivers should call Snapshot/collect + report; signals may be coalesced.
func (a *AppServerSource) Changes() <-chan struct{} { return a.changes }

func (a *AppServerSource) notifyChange() {
	select {
	case a.changes <- struct{}{}:
	default:
	}
}

// Start keeps app-server running (with auto-restart) until ctx is cancelled.
func (a *AppServerSource) Start(ctx context.Context) error {
	ctx, cancel := context.WithCancel(ctx)
	a.cancel = cancel
	go a.supervise(ctx)
	// brief wait for first successful connect (best-effort)
	deadline := time.Now().Add(4 * time.Second)
	for time.Now().Before(deadline) {
		if a.Ready() {
			return nil
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(100 * time.Millisecond):
		}
	}
	// not fatal: supervise keeps trying
	a.logger.Warn("Codex app-server 尚未就绪，将持续重试")
	return nil
}

func (a *AppServerSource) Stop() {
	if a.cancel != nil {
		a.cancel()
	}
	a.killProc()
	a.ready.Store(false)
}

func (a *AppServerSource) Ready() bool { return a.ready.Load() }

func (a *AppServerSource) Snapshot() []apitypes.Session {
	a.sessMu.RLock()
	defer a.sessMu.RUnlock()
	seen := make(map[string]struct{}, len(a.sessions))
	out := make([]apitypes.Session, 0, len(a.sessions))
	for _, s := range a.sessions {
		if _, ok := seen[s.SessionID]; ok {
			continue
		}
		seen[s.SessionID] = struct{}{}
		out = append(out, s)
	}
	return out
}

func (a *AppServerSource) supervise(ctx context.Context) {
	for {
		if ctx.Err() != nil {
			return
		}
		err := a.runOnce(ctx)
		wasReady := a.ready.Swap(false)
		cleared := a.clearSessions()
		a.killProc()
		if cleared {
			a.notifyChange()
		}
		if ctx.Err() != nil {
			return
		}
		if err != nil {
			if wasReady {
				a.logger.Warn("Codex app-server 运行中断，将自动重启", "错误", err, "重启等待", a.opts.RestartDelay.String())
			} else {
				a.logger.Warn("Codex app-server 启动失败，将自动重试", "错误", err, "重试等待", a.opts.RestartDelay.String())
			}
		} else {
			a.logger.Warn("Codex app-server 已退出，将自动重启", "重启等待", a.opts.RestartDelay.String())
		}
		select {
		case <-ctx.Done():
			return
		case <-time.After(a.opts.RestartDelay):
		}
	}
}

func (a *AppServerSource) runOnce(ctx context.Context) error {
	args := []string{"app-server", "--stdio"}
	if mode := strings.TrimSpace(a.opts.SandboxMode); mode != "" {
		// Configurable; never hardcode a dangerous default in code.
		args = append(args, "-c", fmt.Sprintf("sandbox_mode=%q", mode))
	}
	cmd := exec.CommandContext(ctx, "codex", args...)
	stdin, err := cmd.StdinPipe()
	if err != nil {
		return err
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		return err
	}

	if err := cmd.Start(); err != nil {
		return fmt.Errorf("start codex app-server: %w", err)
	}
	a.procMu.Lock()
	a.cmd = cmd
	a.procMu.Unlock()
	a.writeMu.Lock()
	a.stdin = stdin
	a.writeMu.Unlock()
	a.logger.Info("Codex app-server 进程启动成功",
		"沙箱模式", emptyAs(a.opts.SandboxMode, "Codex 默认值"),
		"进程号", cmd.Process.Pid,
	)

	go a.logStderr(stderr)
	go a.readLoop(stdout)
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()

	if err := a.handshake(); err != nil {
		a.killProc()
		return fmt.Errorf("handshake: %w", err)
	}
	a.ready.Store(true)
	a.logger.Info("Codex app-server 通道已就绪")
	a.notifyChange()

	// poll until process dies or ctx cancelled
	poll := time.NewTicker(a.opts.PollInterval)
	defer poll.Stop()

	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case err := <-done:
			return err
		case <-poll.C:
			a.refresh()
		}
	}
}

func (a *AppServerSource) killProc() {
	a.writeMu.Lock()
	if a.stdin != nil {
		_ = a.stdin.Close()
		a.stdin = nil
	}
	a.writeMu.Unlock()
	a.procMu.Lock()
	cmd := a.cmd
	a.cmd = nil
	a.procMu.Unlock()
	if cmd != nil && cmd.Process != nil {
		_ = cmd.Process.Kill()
	}
}

func (a *AppServerSource) logStderr(r io.Reader) {
	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, 0, 16*1024), 256*1024)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" {
			continue
		}
		// bubblewrap / AppArmor / config errors surface here
		low := strings.ToLower(line)
		if strings.Contains(low, "error") || strings.Contains(low, "fail") || strings.Contains(low, "denied") {
			a.logger.Warn("Codex app-server 标准错误", "内容", line)
		} else {
			a.logger.Info("Codex app-server 标准错误", "内容", line)
		}
	}
}

func (a *AppServerSource) readLoop(r io.Reader) {
	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, 0, 64*1024), 8*1024*1024)
	for sc.Scan() {
		line := sc.Bytes()
		if len(line) == 0 {
			continue
		}
		var env map[string]json.RawMessage
		if json.Unmarshal(line, &env) != nil {
			continue
		}
		if idRaw, ok := env["id"]; ok && idRaw != nil {
			var id any
			_ = json.Unmarshal(idRaw, &id)
			key := fmt.Sprint(id)
			if ch, ok := a.waiters.Load(key); ok {
				select {
				case ch.(chan json.RawMessage) <- append(json.RawMessage(nil), line...):
				default:
				}
			}
			continue
		}
		var method string
		_ = json.Unmarshal(env["method"], &method)
		if method != "" {
			a.handleNotify(method, env["params"])
		}
	}
}

func (a *AppServerSource) handleNotify(method string, params json.RawMessage) {
	changed := false
	switch method {
	case "thread/status/changed":
		var p struct {
			ThreadID string          `json:"threadId"`
			Status   json.RawMessage `json:"status"`
		}
		if json.Unmarshal(params, &p) != nil || p.ThreadID == "" {
			return
		}
		state, msg, live := mapThreadStatus(p.Status)
		if !live {
			a.remove(p.ThreadID)
			changed = true
		} else {
			a.upsertPartial(p.ThreadID, state, msg)
			changed = true
		}
	case "turn/started":
		var p struct {
			ThreadID string `json:"threadId"`
		}
		_ = json.Unmarshal(params, &p)
		if p.ThreadID != "" {
			a.upsertPartial(p.ThreadID, apitypes.StateWorking, "turn_started")
			changed = true
		}
	case "turn/completed":
		var p struct {
			ThreadID string `json:"threadId"`
			Turn     struct {
				Status string `json:"status"`
			} `json:"turn"`
		}
		_ = json.Unmarshal(params, &p)
		if p.ThreadID == "" {
			return
		}
		switch p.Turn.Status {
		case "interrupted", "failed":
			a.upsertPartial(p.ThreadID, apitypes.StateIdle, p.Turn.Status)
		default:
			a.upsertPartial(p.ThreadID, apitypes.StateDone, "turn_completed")
		}
		changed = true
	case "thread/closed", "thread/archived", "thread/deleted":
		var p struct {
			ThreadID string `json:"threadId"`
		}
		_ = json.Unmarshal(params, &p)
		if p.ThreadID != "" {
			a.remove(p.ThreadID)
			changed = true
		}
	}
	if changed {
		a.notifyChange()
	}
}

func (a *AppServerSource) remove(id string) {
	a.sessMu.Lock()
	defer a.sessMu.Unlock()
	delete(a.sessions, id)
}

func (a *AppServerSource) upsertPartial(threadID string, state apitypes.SessionState, msg string) {
	a.sessMu.Lock()
	defer a.sessMu.Unlock()
	s, ok := a.sessions[threadID]
	if !ok {
		s = apitypes.Session{
			Agent:       "codex",
			SessionID:   threadID,
			DisplayName: shortID(threadID),
			Source:      "codex-app-server",
		}
	}
	s.State = state
	if sum := ShortSummary(msg, defaultSummaryRunes); sum != "" && !isGenericStatusMessage(sum) {
		s.Message = sum
	} else {
		s.Message = preferMessage(s.Message, msg)
	}
	s.Source = "codex-app-server"
	s.UpdatedAt = time.Now().UTC()
	a.sessions[threadID] = s
}

func (a *AppServerSource) handshake() error {
	if _, err := a.request("initialize", map[string]any{
		"clientInfo": map[string]any{
			"name":    "agent-status-monitor",
			"title":   "Agent Status",
			"version": "0.1.0",
		},
		"capabilities": map[string]any{},
	}, 10*time.Second); err != nil {
		return fmt.Errorf("initialize: %w", err)
	}
	return a.write(map[string]any{"method": "initialized", "params": map[string]any{}})
}

func (a *AppServerSource) refresh() {
	if !a.Ready() {
		return
	}
	before := a.snapshotSignature()
	if err := a.refreshLoaded(); err != nil {
		a.logger.Debug("读取已加载 Codex 会话失败", "错误", err)
	}
	if err := a.refreshList(); err != nil {
		a.logger.Debug("读取 Codex 会话列表失败", "错误", err)
	}
	if a.snapshotSignature() != before {
		a.notifyChange()
	}
}

func (a *AppServerSource) snapshotSignature() string {
	a.sessMu.RLock()
	defer a.sessMu.RUnlock()
	keys := make([]string, 0, len(a.sessions))
	for id := range a.sessions {
		keys = append(keys, id)
	}
	sort.Strings(keys)
	var b strings.Builder
	for _, id := range keys {
		s := a.sessions[id]
		b.WriteString(id)
		b.WriteByte('|')
		b.WriteString(string(s.State))
		b.WriteByte('|')
		b.WriteString(s.Message)
		b.WriteByte(';')
	}
	return b.String()
}

// clearSessions drops stale state from a terminated app-server process.
// The next process rebuilds this cache from its own live thread list.
func (a *AppServerSource) clearSessions() bool {
	a.sessMu.Lock()
	defer a.sessMu.Unlock()
	if len(a.sessions) == 0 {
		return false
	}
	clear(a.sessions)
	return true
}

func (a *AppServerSource) refreshLoaded() error {
	res, err := a.request("thread/loaded/list", map[string]any{}, 8*time.Second)
	if err != nil {
		return err
	}
	threads, err := decodeThreadList(res)
	if err != nil {
		return err
	}
	a.applyThreads(threads, true)
	return nil
}

func (a *AppServerSource) refreshList() error {
	res, err := a.request("thread/list", map[string]any{"limit": 40}, 12*time.Second)
	if err != nil {
		return err
	}
	threads, err := decodeThreadList(res)
	if err != nil {
		return err
	}
	a.applyThreads(threads, false)
	return nil
}

func decodeThreadList(res json.RawMessage) ([]threadDTO, error) {
	var out struct {
		Result struct {
			Data []threadDTO `json:"data"`
		} `json:"result"`
	}
	if err := json.Unmarshal(res, &out); err == nil && out.Result.Data != nil {
		return out.Result.Data, nil
	}
	var alt struct {
		Result []threadDTO `json:"result"`
	}
	if err := json.Unmarshal(res, &alt); err == nil && alt.Result != nil {
		return alt.Result, nil
	}
	return nil, fmt.Errorf("decode thread list")
}

type threadDTO struct {
	ID        string          `json:"id"`
	SessionID string          `json:"sessionId"`
	Status    json.RawMessage `json:"status"`
	Path      string          `json:"path"`
	Cwd       string          `json:"cwd"`
	Name      *string         `json:"name"`
}

func (a *AppServerSource) applyThreads(list []threadDTO, loadedOnly bool) {
	a.sessMu.Lock()
	defer a.sessMu.Unlock()
	now := time.Now().UTC()
	for _, t := range list {
		id := t.ID
		if id == "" {
			id = t.SessionID
		}
		if id == "" {
			continue
		}
		state, msg, live := mapThreadStatus(t.Status)
		if !live {
			if loadedOnly {
				delete(a.sessions, id)
			}
			continue
		}
		display := shortID(id)
		if t.Cwd != "" {
			display = filepath.Base(t.Cwd)
		} else if t.Name != nil && *t.Name != "" {
			display = *t.Name
		}
		sid := id
		if t.Path != "" {
			base := filepath.Base(t.Path)
			base = strings.TrimPrefix(base, "rollout-")
			base = strings.TrimSuffix(base, ".jsonl")
			if base != "" {
				sid = base
			}
		}
		sess := apitypes.Session{
			Agent:       "codex",
			SessionID:   sid,
			DisplayName: display,
			State:       state,
			Message:     firstNonEmpty(msg, "app-server:"+statusType(t.Status)),
			Source:      "codex-app-server",
			UpdatedAt:   now,
		}
		a.sessions[sid] = sess
		if id != sid {
			a.sessions[id] = sess
		}
	}
}

func statusType(raw json.RawMessage) string {
	var s struct {
		Type string `json:"type"`
	}
	_ = json.Unmarshal(raw, &s)
	return s.Type
}

func mapThreadStatus(raw json.RawMessage) (state apitypes.SessionState, msg string, live bool) {
	var s struct {
		Type        string   `json:"type"`
		ActiveFlags []string `json:"activeFlags"`
	}
	if json.Unmarshal(raw, &s) != nil || s.Type == "" {
		return apitypes.StateIdle, "", false
	}
	switch s.Type {
	case "notLoaded":
		return apitypes.StateIdle, "", false
	case "systemError":
		return apitypes.StateIdle, "systemError", true
	case "idle":
		return apitypes.StateIdle, "idle", true
	case "active":
		for _, f := range s.ActiveFlags {
			if f == "waitingOnApproval" || f == "waitingOnUserInput" {
				return apitypes.StateConfirm, f, true
			}
		}
		return apitypes.StateWorking, "active", true
	default:
		return apitypes.StateIdle, s.Type, true
	}
}

func (a *AppServerSource) request(method string, params any, timeout time.Duration) (json.RawMessage, error) {
	id := a.nextID.Add(1)
	ch := make(chan json.RawMessage, 1)
	key := fmt.Sprint(id)
	a.waiters.Store(key, ch)
	defer a.waiters.Delete(key)

	if err := a.write(map[string]any{"method": method, "id": id, "params": params}); err != nil {
		return nil, err
	}
	timer := time.NewTimer(timeout)
	defer timer.Stop()
	select {
	case raw := <-ch:
		var env struct {
			Error *struct {
				Message string `json:"message"`
			} `json:"error"`
		}
		_ = json.Unmarshal(raw, &env)
		if env.Error != nil {
			return nil, fmt.Errorf("%s", env.Error.Message)
		}
		return raw, nil
	case <-timer.C:
		return nil, fmt.Errorf("timeout waiting for %s", method)
	}
}

func (a *AppServerSource) write(v any) error {
	raw, err := json.Marshal(v)
	if err != nil {
		return err
	}
	raw = append(raw, '\n')
	a.writeMu.Lock()
	defer a.writeMu.Unlock()
	if a.stdin == nil {
		return fmt.Errorf("stdin closed")
	}
	_, err = a.stdin.Write(raw)
	return err
}

func firstNonEmpty(vals ...string) string {
	for _, v := range vals {
		if v != "" {
			return v
		}
	}
	return ""
}

func shortID(id string) string {
	if len(id) > 24 {
		return id[:24]
	}
	return id
}

func emptyAs(v, def string) string {
	if strings.TrimSpace(v) == "" {
		return def
	}
	return v
}

// MergeCodexSessions prefers app-server live sessions over file-scanned ones.
func MergeCodexSessions(appSessions, fileSessions []apitypes.Session) []apitypes.Session {
	byID := make(map[string]apitypes.Session, len(fileSessions)+len(appSessions))
	for _, s := range fileSessions {
		byID[s.SessionID] = s
	}
	for _, s := range appSessions {
		if old, ok := byID[s.SessionID]; ok {
			if appBeatsFile(s, old) {
				if s.DisplayName == "" || s.DisplayName == shortID(s.SessionID) {
					s.DisplayName = old.DisplayName
				}
				byID[s.SessionID] = s
			}
		} else {
			byID[s.SessionID] = s
		}
	}
	out := make([]apitypes.Session, 0, len(byID))
	for _, s := range byID {
		out = append(out, s)
	}
	return out
}

func appBeatsFile(app, file apitypes.Session) bool {
	if app.State == apitypes.StateConfirm || app.State == apitypes.StateWorking || app.State == apitypes.StateDone {
		return true
	}
	if app.State == apitypes.StateIdle && file.State == apitypes.StateIdle {
		return true
	}
	return false
}
