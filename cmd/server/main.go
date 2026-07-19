package main

import (
	"flag"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/ynlea/agent-status/internal/server"
	"github.com/ynlea/agent-status/internal/store"
)

func main() {
	addr := flag.String("addr", envOr("AGENT_STATUS_ADDR", ":8080"), "listen address")
	key := flag.String("key", envOr("AGENT_STATUS_KEY", ""), "pre-shared key (required)")
	dbPath := flag.String("db", envOr("AGENT_STATUS_DB", "agent-status.db"), "sqlite path")
	histTTL := flag.Int64("history-ttl-sec", envInt64("AGENT_STATUS_HISTORY_TTL_SEC", 86400), "history TTL seconds")
	histMax := flag.Int("history-max", int(envInt64("AGENT_STATUS_HISTORY_MAX", 50)), "max history rows")
	offlineAfter := flag.Int64("offline-after-sec", envInt64("AGENT_STATUS_OFFLINE_AFTER_SEC", 120), "mark machine offline after N seconds without report")
	cleanupEvery := flag.Duration("cleanup-every", 30*time.Second, "cleanup interval")
	flag.Parse()

	logger := slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	if *key == "" {
		logger.Error("缺少预共享密钥，请设置 -key 或 AGENT_STATUS_KEY")
		os.Exit(2)
	}

	st, err := store.NewSQLite(*dbPath)
	if err != nil {
		logger.Error("打开 SQLite 数据库失败", "错误", err)
		os.Exit(1)
	}
	defer st.Close()

	srv := &server.Server{
		Key:    *key,
		Store:  st,
		Hub:    server.NewHub(),
		Logger: logger,
	}

	stop := make(chan struct{})
	go srv.RunCleanupLoop(stop, *cleanupEvery, *histTTL, *histMax, *offlineAfter)

	httpSrv := &http.Server{Addr: *addr, Handler: srv.Routes()}
	go func() {
		logger.Info("状态服务已开始监听", "监听地址", *addr, "数据库", *dbPath)
		if err := httpSrv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Error("状态服务监听失败", "错误", err)
			os.Exit(1)
		}
	}()

	ch := make(chan os.Signal, 1)
	signal.Notify(ch, syscall.SIGINT, syscall.SIGTERM)
	<-ch
	close(stop)
	_ = httpSrv.Close()
}

func envOr(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func envInt64(k string, def int64) int64 {
	if v := os.Getenv(k); v != "" {
		if n, err := strconv.ParseInt(v, 10, 64); err == nil {
			return n
		}
	}
	return def
}
