package monitor

import (
	"bufio"
	"context"
	"errors"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/fsnotify/fsnotify"
	"github.com/ynlea/agent-status/pkg/apitypes"
)

// CodexFileWatchOptions controls filesystem watching and periodic recovery scans.
type CodexFileWatchOptions struct {
	RescanInterval time.Duration
}

// CodexFileSource watches ordinary Codex rollout files. Each file maintains its
// own read offset, so appending a new JSONL line only reparses that file's delta.
type CodexFileSource struct {
	root           string
	logger         *slog.Logger
	rescanInterval time.Duration
	ready          atomic.Bool

	mu      sync.RWMutex
	watcher *fsnotify.Watcher
	cancel  context.CancelFunc
	watched map[string]struct{}
	files   map[string]*codexTrackedFile
	changes chan struct{}
}

type codexTrackedFile struct {
	offset  int64
	state   codexRolloutState
	session apitypes.Session
	present bool
}

func NewCodexFileSource(root string, logger *slog.Logger, opts CodexFileWatchOptions) *CodexFileSource {
	if logger == nil {
		logger = slog.Default()
	}
	if opts.RescanInterval <= 0 {
		// Windows file notifications are easier to miss under bursty appends;
		// keep a tighter light rescan so detail updates do not wait a full minute.
		if runtime.GOOS == "windows" {
			opts.RescanInterval = 15 * time.Second
		} else {
			opts.RescanInterval = time.Minute
		}
	}
	return &CodexFileSource{
		root:           root,
		logger:         logger,
		rescanInterval: opts.RescanInterval,
		watched:        make(map[string]struct{}),
		files:          make(map[string]*codexTrackedFile),
		changes:        make(chan struct{}, 1),
	}
}

// Start begins recursive directory watching and an initial state rebuild.
func (s *CodexFileSource) Start(ctx context.Context) error {
	if s.root == "" {
		return errors.New("Codex 会话目录为空")
	}
	w, err := fsnotify.NewWatcher()
	if err != nil {
		return err
	}
	if err := s.watchTree(w, s.root); err != nil {
		_ = w.Close()
		return err
	}
	s.mu.Lock()
	s.watcher = w
	s.mu.Unlock()
	if err := s.rescan(); err != nil {
		_ = w.Close()
		return err
	}

	ctx, cancel := context.WithCancel(ctx)
	s.cancel = cancel
	s.ready.Store(true)
	s.logger.Info("Codex 会话文件监听已启动", "目录", s.root, "轻量校准间隔", s.rescanInterval.String())
	go s.loop(ctx, w)
	return nil
}

func (s *CodexFileSource) Stop() {
	if s.cancel != nil {
		s.cancel()
	}
	s.mu.Lock()
	w := s.watcher
	s.watcher = nil
	s.mu.Unlock()
	if w != nil {
		_ = w.Close()
	}
	s.ready.Store(false)
}

func (s *CodexFileSource) Ready() bool { return s.ready.Load() }

func (s *CodexFileSource) Changes() <-chan struct{} { return s.changes }

func (s *CodexFileSource) Snapshot() []apitypes.Session {
	s.mu.RLock()
	out := make([]apitypes.Session, 0, len(s.files))
	for _, file := range s.files {
		if file.present {
			session := file.session
			session.Source = "codex-file-watch"
			out = append(out, session)
		}
	}
	s.mu.RUnlock()
	sort.Slice(out, func(i, j int) bool { return out[i].SessionID < out[j].SessionID })
	return out
}

func (s *CodexFileSource) loop(ctx context.Context, w *fsnotify.Watcher) {
	ticker := time.NewTicker(s.rescanInterval)
	defer ticker.Stop()
	defer s.ready.Store(false)
	for {
		select {
		case <-ctx.Done():
			return
		case err, ok := <-w.Errors:
			if !ok {
				return
			}
			s.logger.Warn("Codex 会话文件监听发生错误", "错误", err)
		case event, ok := <-w.Events:
			if !ok {
				return
			}
			s.handleEvent(w, event)
		case <-ticker.C:
			if err := s.rescan(); err != nil {
				s.logger.Warn("Codex 会话文件轻量校准失败", "错误", err)
			}
		}
	}
}

func (s *CodexFileSource) handleEvent(w *fsnotify.Watcher, event fsnotify.Event) {
	if event.Op&fsnotify.Create != 0 {
		if info, err := os.Stat(event.Name); err == nil && info.IsDir() {
			if err := s.watchTree(w, event.Name); err != nil {
				s.logger.Warn("添加 Codex 会话目录监听失败", "目录", event.Name, "错误", err)
				return
			}
			if err := s.rescan(); err != nil {
				s.logger.Warn("发现新目录后的 Codex 会话校准失败", "错误", err)
			}
			return
		}
	}

	if !isCodexRollout(event.Name) {
		if event.Op&(fsnotify.Remove|fsnotify.Rename) != 0 {
			if err := s.rescan(); err != nil {
				s.logger.Warn("Codex 会话目录变化后的校准失败", "错误", err)
			}
		}
		return
	}
	if event.Op&(fsnotify.Remove|fsnotify.Rename) != 0 {
		s.removeFile(event.Name)
		return
	}
	// Write is the normal append path. On some Windows setups appends also
	// surface as Chmod-only notifications; treat both as content changes.
	if event.Op&(fsnotify.Create|fsnotify.Write|fsnotify.Chmod) != 0 {
		s.updateFile(event.Name)
	}
}

func (s *CodexFileSource) watchTree(w *fsnotify.Watcher, root string) error {
	return filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if !d.IsDir() {
			return nil
		}
		s.mu.Lock()
		_, exists := s.watched[path]
		if !exists {
			if addErr := w.Add(path); addErr == nil {
				s.watched[path] = struct{}{}
			} else {
				s.mu.Unlock()
				return addErr
			}
		}
		s.mu.Unlock()
		return nil
	})
}

// rescan recovers missed filesystem events without re-reading unchanged files.
// New/truncated/appended files are reconciled; size-stable files only re-evaluate
// time-based idle transitions from the cached rollout state.
func (s *CodexFileSource) rescan() error {
	s.mu.RLock()
	w := s.watcher
	s.mu.RUnlock()
	if w != nil {
		if err := s.watchTree(w, s.root); err != nil {
			s.logger.Warn("校准阶段补充目录监听失败", "错误", err)
		}
	}

	found := make(map[string]struct{})
	err := filepath.WalkDir(s.root, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() {
			return nil
		}
		if isCodexRollout(path) {
			found[path] = struct{}{}
			s.reconcileFile(path)
		}
		return nil
	})
	if err != nil {
		return err
	}

	changed := false
	s.mu.Lock()
	for path := range s.files {
		if _, ok := found[path]; !ok {
			delete(s.files, path)
			changed = true
		}
	}
	s.mu.Unlock()
	if changed {
		s.notifyChange()
	}
	return nil
}

// reconcileFile is the cheap recovery path: Stat first, then read only when needed.
func (s *CodexFileSource) reconcileFile(path string) {
	info, err := os.Stat(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			s.removeFile(path)
		}
		return
	}

	s.mu.RLock()
	file, exists := s.files[path]
	var offset int64
	if exists {
		offset = file.offset
	}
	s.mu.RUnlock()

	switch {
	case !exists || info.Size() < offset:
		s.reloadFile(path)
	case info.Size() > offset:
		s.updateFile(path)
	default:
		s.refreshDerived(path, info.ModTime().UTC())
	}
}

// refreshDerived re-applies idle/drop rules without reading the file body.
func (s *CodexFileSource) refreshDerived(path string, modTime time.Time) {
	s.mu.Lock()
	file, exists := s.files[path]
	if !exists {
		s.mu.Unlock()
		return
	}
	next, present := file.state.session(modTime, time.Now().UTC())
	changed := !sameCodexSession(file.session, file.present, next, present)
	file.session = next
	file.present = present
	s.mu.Unlock()
	if changed {
		s.notifyChange()
	}
}

func (s *CodexFileSource) reloadFile(path string) {
	state, offset, session, ok := loadCodexRollout(path)
	if state.sessionID == "" {
		return
	}
	s.mu.Lock()
	old, existed := s.files[path]
	changed := !existed || !sameCodexSession(old.session, old.present, session, ok)
	s.files[path] = &codexTrackedFile{offset: offset, state: state, session: session, present: ok}
	s.mu.Unlock()
	if changed {
		s.notifyChange()
	}
}

func (s *CodexFileSource) updateFile(path string) {
	info, err := os.Stat(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			s.removeFile(path)
		}
		return
	}

	s.mu.RLock()
	file, exists := s.files[path]
	needReload := !exists || info.Size() < file.offset
	s.mu.RUnlock()
	if needReload {
		s.reloadFile(path)
		return
	}
	if info.Size() == file.offset {
		return
	}

	f, err := os.Open(path)
	if err != nil {
		return
	}
	defer f.Close()
	if _, err := f.Seek(file.offset, io.SeekStart); err != nil {
		s.reloadFile(path)
		return
	}

	reader := bufio.NewReaderSize(f, 64*1024)
	var lines []string
	var advance int64
	for {
		line, readErr := reader.ReadString('\n')
		if len(line) > 0 && strings.HasSuffix(line, "\n") {
			advance += int64(len(line))
			line = strings.TrimSuffix(line, "\n")
			line = strings.TrimSuffix(line, "\r")
			if line != "" {
				lines = append(lines, line)
			}
		}
		if readErr == io.EOF {
			break
		}
		if readErr != nil {
			return
		}
	}
	if advance == 0 {
		return
	}

	s.mu.Lock()
	file, exists = s.files[path]
	if !exists || info.Size() < file.offset {
		s.mu.Unlock()
		s.reloadFile(path)
		return
	}
	for _, line := range lines {
		file.state.applyLine(line, info.ModTime().UTC())
	}
	file.offset += advance
	next, present := file.state.session(info.ModTime().UTC(), time.Now().UTC())
	changed := !sameCodexSession(file.session, file.present, next, present)
	file.session = next
	file.present = present
	s.mu.Unlock()
	if changed {
		s.notifyChange()
	}
}

func (s *CodexFileSource) removeFile(path string) {
	s.mu.Lock()
	_, exists := s.files[path]
	delete(s.files, path)
	s.mu.Unlock()
	if exists {
		s.notifyChange()
	}
}

func (s *CodexFileSource) notifyChange() {
	select {
	case s.changes <- struct{}{}:
	default:
	}
}

func isCodexRollout(path string) bool {
	base := filepath.Base(path)
	return strings.HasPrefix(base, "rollout-") && strings.HasSuffix(base, ".jsonl")
}

func sameCodexSession(old apitypes.Session, oldPresent bool, next apitypes.Session, nextPresent bool) bool {
	return oldPresent == nextPresent &&
		old.SessionID == next.SessionID &&
		old.DisplayName == next.DisplayName &&
		old.State == next.State &&
		old.Message == next.Message &&
		old.Cwd == next.Cwd &&
		// Detail text streams in while state stays "working"; must trigger report.
		old.LastAssistantMessage == next.LastAssistantMessage
}
