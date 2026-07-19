package monitor

import (
	"encoding/json"
	"log/slog"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/ynlea/agent-status/pkg/apitypes"
)

type fileCursor struct {
	Offset int64 `json:"offset"`
	Size   int64 `json:"size"`
}

type usageState struct {
	BackfillDone bool                  `json:"backfill_done"`
	Files        map[string]fileCursor `json:"files"`
}

// UsageSyncer scans local Claude/Codex logs and reports usage events.
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
	return u
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

// SyncOnce scans and reports. full=true forces reading from offset 0 for unknown files
// but still uses cursors when present; first run walks all history.
func (u *UsageSyncer) SyncOnce() error {
	u.mu.Lock()
	defer u.mu.Unlock()

	var files []struct {
		path  string
		kind  string // claude|codex
	}
	claudeFiles, _ := CollectClaudeUsageFiles(u.Cfg.ClaudeProjectsDir)
	for _, p := range claudeFiles {
		files = append(files, struct {
			path string
			kind string
		}{p, "claude"})
	}
	codexFiles, _ := CollectCodexUsageFiles(u.Cfg.CodexSessionsDir)
	for _, p := range codexFiles {
		files = append(files, struct {
			path string
			kind string
		}{p, "codex"})
	}

	var batch []apitypes.UsageEvent
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
				// put back and fail
				batch = append(chunk, batch...)
				return err
			}
		}
		return nil
	}

	for _, f := range files {
		info, err := os.Stat(f.path)
		if err != nil {
			continue
		}
		cur := u.state.Files[f.path]
		// truncated or replaced
		if cur.Size > info.Size() || (cur.Offset > info.Size()) {
			cur = fileCursor{}
		}
		var events []apitypes.UsageEvent
		var newOff int64
		switch f.kind {
		case "claude":
			events, newOff, err = ParseClaudeUsageFile(f.path, cur.Offset)
		default:
			events, newOff, err = ParseCodexUsageFile(f.path, cur.Offset)
		}
		if err != nil {
			u.Logger.Warn("解析用量日志失败", "路径", f.path, "错误", err)
			continue
		}
		if len(events) > 0 {
			batch = append(batch, events...)
			if err := flush(false); err != nil {
				return err
			}
		}
		u.state.Files[f.path] = fileCursor{Offset: newOff, Size: info.Size()}
	}
	if err := flush(true); err != nil {
		return err
	}
	u.state.BackfillDone = true
	if err := u.save(); err != nil {
		u.Logger.Warn("保存用量游标失败", "错误", err)
	}
	return nil
}

// RunLoop periodic usage sync.
func (u *UsageSyncer) RunLoop(stop <-chan struct{}) {
	interval := time.Duration(u.Cfg.UsageIntervalSec) * time.Second
	if interval <= 0 {
		interval = 10 * time.Minute
	}
	// first pass ASAP (full history via offset 0)
	if err := u.SyncOnce(); err != nil {
		u.Logger.Warn("用量首次同步失败", "错误", err)
	} else {
		u.Logger.Info("用量同步完成", "回填完成", u.state.BackfillDone, "文件数", len(u.state.Files))
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
