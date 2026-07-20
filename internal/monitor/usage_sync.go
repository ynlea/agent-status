package monitor

import (
	"encoding/json"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/ynlea/agent-status/pkg/apitypes"
)

type fileCursor struct {
	Offset    int64  `json:"offset"`
	Size      int64  `json:"size"`
	Kind      string `json:"kind,omitempty"` // claude|codex
	LastModel string `json:"last_model,omitempty"`
}

type usageState struct {
	ServerURL          string                `json:"server_url,omitempty"`
	BackfillDone       bool                  `json:"backfill_done"`
	LastDiscoverUnix   int64                 `json:"last_discover_unix,omitempty"`
	CodexModelHealDone bool                  `json:"codex_model_heal_done,omitempty"`
	Files              map[string]fileCursor `json:"files"`
}

// UsageSyncer scans local Claude/Codex logs and reports usage events.
// Designed for frequent ticks (e.g. 1 minute):
//   - known files: Stat only; open/parse only when size > cursor
//   - directory discovery: slower cadence (default 10 minutes)
//   - cursor persistence only when something actually changed
type UsageSyncer struct {
	Cfg    *Config
	Rep    *Reporter
	Logger *slog.Logger

	mu    sync.Mutex
	state usageState
	path  string
}

func NewUsageSyncer(cfg *Config, rep *Reporter, logger *slog.Logger) *UsageSyncer {
	if logger == nil {
		logger = slog.Default()
	}
	path := cfg.UsageStateFile
	if path == "" {
		home, _ := os.UserHomeDir()
		path = filepath.Join(home, ".agent-status", "usage-cursors.json")
	}
	u := &UsageSyncer{Cfg: cfg, Rep: rep, Logger: logger, path: path}
	u.state.Files = map[string]fileCursor{}
	_ = u.load()
	u.rebindServerIfNeeded()
	return u
}

func normalizeServerURL(raw string) string {
	s := strings.TrimSpace(raw)
	for strings.HasSuffix(s, "/") {
		s = strings.TrimSuffix(s, "/")
	}
	return s
}

// rebindServerIfNeeded resets local cursors when the configured server changes,
// so a fresh/empty server receives a full historical backfill.
func (u *UsageSyncer) rebindServerIfNeeded() {
	target := ""
	if u.Cfg != nil {
		target = normalizeServerURL(u.Cfg.ServerURL)
	}
	if target == "" {
		return
	}
	if normalizeServerURL(u.state.ServerURL) == target {
		return
	}
	u.Logger.Info("用量游标绑定服务端已变化，将全量重传",
		"原服务地址", u.state.ServerURL,
		"新服务地址", target,
		"原文件数", len(u.state.Files),
	)
	u.state = usageState{
		ServerURL:    target,
		BackfillDone: false,
		Files:        map[string]fileCursor{},
	}
}

func (u *UsageSyncer) load() error {
	data, err := os.ReadFile(u.path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	var st usageState
	if err := json.Unmarshal(data, &st); err != nil {
		return err
	}
	if st.Files == nil {
		st.Files = map[string]fileCursor{}
	}
	for path, cur := range st.Files {
		if cur.Kind == "" {
			cur.Kind = inferUsageKind(path)
			st.Files[path] = cur
		}
	}
	u.state = st
	return nil
}

func (u *UsageSyncer) save() error {
	if err := os.MkdirAll(filepath.Dir(u.path), 0o755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(u.state, "", "  ")
	if err != nil {
		return err
	}
	tmp := u.path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, u.path)
}

func (u *UsageSyncer) discoverInterval() time.Duration {
	sec := 0
	if u.Cfg != nil {
		sec = u.Cfg.UsageDiscoverSec
	}
	if sec <= 0 {
		sec = 600
	}
	return time.Duration(sec) * time.Second
}

func (u *UsageSyncer) shouldDiscover(now time.Time) bool {
	if !u.state.BackfillDone {
		return true
	}
	if u.state.LastDiscoverUnix <= 0 {
		return true
	}
	last := time.Unix(u.state.LastDiscoverUnix, 0)
	return now.Sub(last) >= u.discoverInterval()
}

// SyncOnce reconciles usage events once.
// Hot path avoids re-reading unchanged files so a 1-minute tick stays cheap.
func (u *UsageSyncer) SyncOnce() error {
	u.mu.Lock()
	defer u.mu.Unlock()

	u.rebindServerIfNeeded()

	now := time.Now().UTC()
	dirty := false
	if u.healCodexUnknownModels() {
		dirty = true
	}
	doDiscover := u.shouldDiscover(now)

	if doDiscover {
		if u.discoverFiles() {
			dirty = true
		}
		u.state.LastDiscoverUnix = now.Unix()
		dirty = true
	}

	var batch []apitypes.UsageEvent
	// pending holds file advances that must not stick if their events fail to upload.
	type pendingAdvance struct {
		path string
		cur  fileCursor
	}
	var pending []pendingAdvance

	commitPending := func() {
		for _, p := range pending {
			u.state.Files[p.path] = p.cur
			dirty = true
		}
		pending = pending[:0]
	}

	flush := func(force bool) error {
		if len(batch) == 0 {
			return nil
		}
		if !force && len(batch) < 400 {
			return nil
		}
		for len(batch) > 0 {
			n := 500
			if n > len(batch) {
				n = len(batch)
			}
			chunk := batch[:n]
			batch = batch[n:]
			if err := u.Rep.ReportUsage(chunk); err != nil {
				batch = append(chunk, batch...)
				return err
			}
		}
		// Only advance file cursors after the related batches uploaded successfully.
		commitPending()
		return nil
	}

	for path, cur := range u.state.Files {
		info, err := os.Stat(path)
		if err != nil {
			if os.IsNotExist(err) {
				delete(u.state.Files, path)
				dirty = true
			}
			continue
		}

		// Truncated / replaced: restart from 0.
		if cur.Size > info.Size() || cur.Offset > info.Size() {
			cur = fileCursor{Kind: usageKindOrInfer(cur.Kind, path), LastModel: cur.LastModel}
			dirty = true
		}

		// Fully caught up and size stable: no open, no parse.
		if info.Size() == cur.Offset {
			if cur.Size != info.Size() || cur.Kind == "" {
				cur.Size = info.Size()
				cur.Kind = usageKindOrInfer(cur.Kind, path)
				u.state.Files[path] = cur
				dirty = true
			}
			continue
		}

		kind := usageKindOrInfer(cur.Kind, path)
		var events []apitypes.UsageEvent
		var newOff int64
		lastModel := cur.LastModel
		switch kind {
		case "claude":
			events, newOff, err = ParseClaudeUsageFile(path, cur.Offset)
		default:
			events, newOff, lastModel, err = ParseCodexUsageFile(path, cur.Offset, cur.LastModel)
		}
		if err != nil {
			u.Logger.Warn("解析用量日志失败", "路径", path, "错误", err)
			continue
		}
		next := fileCursor{Offset: newOff, Size: info.Size(), Kind: kind, LastModel: lastModel}
		if len(events) > 0 {
			batch = append(batch, events...)
			pending = append(pending, pendingAdvance{path: path, cur: next})
			if err := flush(false); err != nil {
				// Keep successful progress; never mark backfill complete on failure.
				u.state.BackfillDone = false
				if dirty {
					if saveErr := u.save(); saveErr != nil {
						u.Logger.Warn("保存用量游标失败", "错误", saveErr)
					}
				}
				return err
			}
		} else {
			// No events: advancing offset is local-only and safe.
			u.state.Files[path] = next
			dirty = true
		}
	}

	if err := flush(true); err != nil {
		u.state.BackfillDone = false
		if dirty {
			if saveErr := u.save(); saveErr != nil {
				u.Logger.Warn("保存用量游标失败", "错误", saveErr)
			}
		}
		return err
	}
	if !u.state.BackfillDone {
		u.state.BackfillDone = true
		dirty = true
	}
	if u.Cfg != nil {
		if norm := normalizeServerURL(u.Cfg.ServerURL); norm != "" && u.state.ServerURL != norm {
			u.state.ServerURL = norm
			dirty = true
		}
	}
	if dirty {
		if err := u.save(); err != nil {
			u.Logger.Warn("保存用量游标失败", "错误", err)
		}
	}
	return nil
}

// healCodexUnknownModels once resets Codex cursors so events previously
// stored as model=unknown can be re-reported (server fills model on conflict).
func (u *UsageSyncer) healCodexUnknownModels() bool {
	if u.state.CodexModelHealDone {
		return false
	}
	changed := false
	for path, cur := range u.state.Files {
		kind := usageKindOrInfer(cur.Kind, path)
		if kind != "codex" {
			continue
		}
		// Force a full re-read; LastModel is rebuilt during parse.
		_ = cur
		u.state.Files[path] = fileCursor{Kind: kind}
		changed = true
	}
	u.state.CodexModelHealDone = true
	if changed {
		u.Logger.Info("用量修复：重扫 Codex 日志以回填模型名", "文件数", len(u.state.Files))
	}
	return true
}

// discoverFiles walks roots and registers new jsonl paths. Returns true if the map changed.
func (u *UsageSyncer) discoverFiles() bool {
	changed := false
	found := make(map[string]struct{})

	add := func(path, kind string) {
		found[path] = struct{}{}
		if cur, ok := u.state.Files[path]; ok {
			if cur.Kind == "" {
				cur.Kind = kind
				u.state.Files[path] = cur
				changed = true
			}
			return
		}
		u.state.Files[path] = fileCursor{Kind: kind}
		changed = true
	}

	claudeFiles, _ := CollectClaudeUsageFiles(u.Cfg.ClaudeProjectsDir)
	for _, p := range claudeFiles {
		add(p, "claude")
	}
	codexFiles, _ := CollectCodexUsageFiles(u.Cfg.CodexSessionsDir)
	for _, p := range codexFiles {
		add(p, "codex")
	}

	// Drop files that disappeared (only when we have a full inventory).
	for path := range u.state.Files {
		if _, ok := found[path]; !ok {
			delete(u.state.Files, path)
			changed = true
		}
	}
	return changed
}

// RunLoop periodic usage sync.
func (u *UsageSyncer) RunLoop(stop <-chan struct{}) {
	interval := time.Duration(u.Cfg.UsageIntervalSec) * time.Second
	if interval <= 0 {
		interval = time.Minute
	}
	if err := u.SyncOnce(); err != nil {
		u.Logger.Warn("用量首次同步失败", "错误", err)
	} else {
		u.Logger.Info("用量同步完成",
			"回填完成", u.state.BackfillDone,
			"文件数", len(u.state.Files),
			"扫描间隔秒", int(interval.Seconds()),
			"发现间隔秒", int(u.discoverInterval().Seconds()),
		)
	}
	t := time.NewTicker(interval)
	defer t.Stop()
	for {
		select {
		case <-stop:
			return
		case <-t.C:
			if err := u.SyncOnce(); err != nil {
				u.Logger.Warn("用量定时同步失败", "错误", err)
			}
		}
	}
}

func inferUsageKind(path string) string {
	base := filepath.Base(path)
	if strings.HasPrefix(base, "rollout-") && strings.HasSuffix(base, ".jsonl") {
		return "codex"
	}
	return "claude"
}

func usageKindOrInfer(kind, path string) string {
	if kind == "claude" || kind == "codex" {
		return kind
	}
	return inferUsageKind(path)
}
