package pricing

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/ynlea/agent-status/internal/store"
)

type memWriter struct {
	prices map[string]store.ModelPrice
	source map[string]string
}

func newMemWriter() *memWriter {
	return &memWriter{prices: map[string]store.ModelPrice{}, source: map[string]string{}}
}

func (m *memWriter) UpsertModelPrice(p store.ModelPrice, source string) error {
	id := store.NormalizeModelID(p.ModelID)
	if id == "" {
		return nil
	}
	if m.source[id] == store.SourceOverride && source != store.SourceOverride {
		return nil
	}
	p.ModelID = id
	p.Source = source
	m.prices[id] = p
	m.source[id] = source
	return nil
}

func TestMapOpenRouterModel(t *testing.T) {
	p, ok := MapOpenRouterModel("anthropic/claude-sonnet-4.5", "0.000003", "0.000015")
	if !ok {
		t.Fatal("expected map ok")
	}
	if p.ModelID != "claude-sonnet-4-5" {
		t.Fatalf("id=%s", p.ModelID)
	}
	if p.InputPerM != 3 || p.OutputPerM != 15 {
		t.Fatalf("prices in=%v out=%v", p.InputPerM, p.OutputPerM)
	}
}

func TestSyncOpenRouterHTTP(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/v1/models" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"data":[
			{"id":"anthropic/claude-haiku-4.5","pricing":{"prompt":"0.000001","completion":"0.000005"}},
			{"id":"bad/model","pricing":{"prompt":"x","completion":"1"}}
		]}`))
	}))
	defer srv.Close()

	w := newMemWriter()
	// protect override
	_ = w.UpsertModelPrice(store.ModelPrice{
		ModelID: "claude-haiku-4-5", InputPerM: 9, OutputPerM: 9, CacheReadPerM: 0.1, CacheWritePerM: 1.25,
	}, store.SourceOverride)

	res, err := SyncOpenRouter(context.Background(), Config{
		BaseURL:    srv.URL + "/api/v1",
		HTTPClient: srv.Client(),
	}, w)
	if err != nil {
		t.Fatal(err)
	}
	if res.Fetched != 2 || res.Upserted != 1 || res.Skipped != 1 {
		t.Fatalf("result=%+v", res)
	}
	p := w.prices["claude-haiku-4-5"]
	if p.InputPerM != 9 || p.Source != store.SourceOverride {
		t.Fatalf("override overwritten: %+v", p)
	}
}

func TestSyncHTTPError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "nope", 500)
	}))
	defer srv.Close()
	_, err := SyncOpenRouter(context.Background(), Config{
		BaseURL:    srv.URL + "/api/v1",
		HTTPClient: srv.Client(),
	}, newMemWriter())
	if err == nil {
		t.Fatal("expected error")
	}
}
