package pricing

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/ynlea/agent-status/internal/store"
)

// Config controls OpenRouter price sync.
type Config struct {
	// BaseURL is e.g. https://openrouter.ai/api/v1 (no trailing slash required).
	BaseURL string
	APIKey  string
	// HTTPClient optional; default has 30s timeout.
	HTTPClient *http.Client
}

// Result summarizes a sync run.
type Result struct {
	Fetched  int
	Upserted int
	Skipped  int
}

type openRouterResponse struct {
	Data []openRouterModel `json:"data"`
}

type openRouterModel struct {
	ID      string            `json:"id"`
	Name    string            `json:"name"`
	Pricing openRouterPricing `json:"pricing"`
}

type openRouterPricing struct {
	Prompt     string `json:"prompt"`
	Completion string `json:"completion"`
}

// PriceWriter is the subset of store used by sync.
type PriceWriter interface {
	UpsertModelPrice(p store.ModelPrice, source string) error
}

// SyncOpenRouter pulls model list and upserts prices. Failures return error; partial upserts may have applied.
func SyncOpenRouter(ctx context.Context, cfg Config, w PriceWriter) (Result, error) {
	var res Result
	if w == nil {
		return res, fmt.Errorf("nil price writer")
	}
	base := strings.TrimRight(cfg.BaseURL, "/")
	if base == "" {
		base = "https://openrouter.ai/api/v1"
	}
	client := cfg.HTTPClient
	if client == nil {
		client = &http.Client{Timeout: 30 * time.Second}
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, base+"/models", nil)
	if err != nil {
		return res, err
	}
	req.Header.Set("User-Agent", "agent-status-pricing/1.0")
	req.Header.Set("Accept", "application/json")
	if cfg.APIKey != "" {
		req.Header.Set("Authorization", "Bearer "+cfg.APIKey)
	}
	resp, err := client.Do(req)
	if err != nil {
		return res, err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 32<<20))
	if err != nil {
		return res, err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return res, fmt.Errorf("openrouter models: HTTP %d: %s", resp.StatusCode, truncate(string(body), 200))
	}
	var parsed openRouterResponse
	if err := json.Unmarshal(body, &parsed); err != nil {
		return res, fmt.Errorf("openrouter models json: %w", err)
	}
	res.Fetched = len(parsed.Data)
	for _, m := range parsed.Data {
		p, ok := MapOpenRouterModel(m.ID, m.Pricing.Prompt, m.Pricing.Completion)
		if !ok {
			res.Skipped++
			continue
		}
		if err := w.UpsertModelPrice(p, store.SourceOpenRouter); err != nil {
			return res, err
		}
		res.Upserted++
	}
	return res, nil
}

// MapOpenRouterModel converts per-token USD strings to ModelPrice (USD / 1M).
func MapOpenRouterModel(id, prompt, completion string) (store.ModelPrice, bool) {
	id = strings.TrimSpace(id)
	if id == "" {
		return store.ModelPrice{}, false
	}
	in, ok1 := perTokenToPerM(prompt)
	out, ok2 := perTokenToPerM(completion)
	if !ok1 || !ok2 {
		return store.ModelPrice{}, false
	}
	norm := store.NormalizeModelID(id)
	if norm == "" {
		return store.ModelPrice{}, false
	}
	return store.ModelPrice{
		ModelID:    norm,
		InputPerM:  in,
		OutputPerM: out,
		Source:     store.SourceOpenRouter,
	}, true
}

func perTokenToPerM(s string) (float64, bool) {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0, false
	}
	f, err := strconv.ParseFloat(s, 64)
	if err != nil || f < 0 {
		return 0, false
	}
	return f * 1e6, true
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "..."
}

// RunLoop periodically syncs until ctx is done. First sync runs immediately when onStart is true.
func RunLoop(ctx context.Context, cfg Config, w PriceWriter, interval time.Duration, onStart bool, log func(string, ...any)) {
	if interval <= 0 {
		interval = 24 * time.Hour
	}
	if log == nil {
		log = func(string, ...any) {}
	}
	do := func() {
		res, err := SyncOpenRouter(ctx, cfg, w)
		if err != nil {
			log("openrouter price sync failed", "error", err)
			return
		}
		log("openrouter price sync ok", "fetched", res.Fetched, "upserted", res.Upserted, "skipped", res.Skipped)
	}
	if onStart {
		do()
	}
	t := time.NewTicker(interval)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			do()
		}
	}
}
