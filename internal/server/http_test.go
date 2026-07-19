package server

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gorilla/websocket"
	"github.com/ynlea/agent-status/internal/store"
	"github.com/ynlea/agent-status/pkg/apitypes"
)

func TestReportQueryAndWS(t *testing.T) {
	srv := &Server{
		Key:   "dev-secret",
		Store: store.NewMemory(50),
		Hub:   NewHub(),
	}
	ts := httptest.NewServer(srv.Routes())
	defer ts.Close()

	// unauthorized
	res, err := http.Get(ts.URL + "/api/v1/machines")
	if err != nil {
		t.Fatal(err)
	}
	res.Body.Close()
	if res.StatusCode != http.StatusUnauthorized {
		t.Fatalf("status=%d", res.StatusCode)
	}

	// WS client first
	wsURL := "ws" + ts.URL[len("http"):] + "/api/v1/ws"
	hdr := http.Header{}
	hdr.Set("Authorization", "Bearer dev-secret")
	conn, _, err := websocket.DefaultDialer.Dial(wsURL, hdr)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()

	events := make(chan apitypes.WSEvent, 8)
	go func() {
		for {
			_, data, err := conn.ReadMessage()
			if err != nil {
				return
			}
			var ev apitypes.WSEvent
			if json.Unmarshal(data, &ev) == nil {
				events <- ev
			}
		}
	}()

	body := map[string]interface{}{
		"machine_id":   "m1",
		"machine_name": "desk-linux",
		"platform":     "linux",
		"reported_at":  time.Now().UTC().Format(time.RFC3339),
		"sessions": []map[string]interface{}{{
			"agent":        "claude",
			"session_id":   "s1",
			"display_name": "demo",
			"state":        "confirm",
			"updated_at":   time.Now().UTC().Format(time.RFC3339),
		}},
	}
	raw, _ := json.Marshal(body)
	req, _ := http.NewRequest(http.MethodPost, ts.URL+"/api/v1/report", bytes.NewReader(raw))
	req.Header.Set("Authorization", "Bearer dev-secret")
	req.Header.Set("Content-Type", "application/json")
	res, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	res.Body.Close()
	if res.StatusCode != http.StatusOK {
		t.Fatalf("report status=%d", res.StatusCode)
	}

	// GET machines
	req, _ = http.NewRequest(http.MethodGet, ts.URL+"/api/v1/machines", nil)
	req.Header.Set("Authorization", "Bearer dev-secret")
	res, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	var machines struct {
		Machines []apitypes.Machine `json:"machines"`
	}
	_ = json.NewDecoder(res.Body).Decode(&machines)
	res.Body.Close()
	if len(machines.Machines) != 1 {
		t.Fatalf("machines=%v", machines)
	}

	// GET sessions
	req, _ = http.NewRequest(http.MethodGet, ts.URL+"/api/v1/machines/m1/sessions", nil)
	req.Header.Set("Authorization", "Bearer dev-secret")
	res, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	var sessions struct {
		Sessions []apitypes.Session `json:"sessions"`
	}
	_ = json.NewDecoder(res.Body).Decode(&sessions)
	res.Body.Close()
	if len(sessions.Sessions) != 1 || sessions.Sessions[0].State != apitypes.StateConfirm {
		t.Fatalf("sessions=%v", sessions)
	}

	// expect WS events
	deadline := time.After(2 * time.Second)
	gotUpsert, gotNotify := false, false
	for !gotUpsert || !gotNotify {
		select {
		case ev := <-events:
			if ev.Type == apitypes.WSSessionUpsert {
				gotUpsert = true
			}
			if ev.Type == apitypes.WSNotification {
				gotNotify = true
			}
		case <-deadline:
			t.Fatalf("timeout waiting for ws events upsert=%v notify=%v", gotUpsert, gotNotify)
		}
	}
}


func TestUsageReportAndQuery(t *testing.T) {
	srv := &Server{
		Key:   "dev-secret",
		Store: store.NewMemory(50),
		Hub:   NewHub(),
	}
	ts := httptest.NewServer(srv.Routes())
	defer ts.Close()

	now := time.Now().UTC().Truncate(time.Second)
	body := map[string]interface{}{
		"machine_id":   "m1",
		"machine_name": "desk",
		"platform":     "linux",
		"reported_at":  now.Format(time.RFC3339),
		"events": []map[string]interface{}{{
			"dedupe_key":        "k1",
			"agent":             "claude",
			"model":             "claude-sonnet-4-5",
			"occurred_at":       now.Format(time.RFC3339),
			"input_tokens":      100,
			"output_tokens":     20,
			"cache_hit_tokens":  400,
		}},
	}
	raw, _ := json.Marshal(body)
	req, _ := http.NewRequest(http.MethodPost, ts.URL+"/api/v1/usage/report", bytes.NewReader(raw))
	req.Header.Set("Authorization", "Bearer dev-secret")
	req.Header.Set("Content-Type", "application/json")
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	if res.StatusCode != http.StatusOK {
		t.Fatalf("status=%d", res.StatusCode)
	}
	res.Body.Close()

	// replay duplicate
	req, _ = http.NewRequest(http.MethodPost, ts.URL+"/api/v1/usage/report", bytes.NewReader(raw))
	req.Header.Set("Authorization", "Bearer dev-secret")
	req.Header.Set("Content-Type", "application/json")
	res, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	var rep apitypes.UsageReportResponse
	_ = json.NewDecoder(res.Body).Decode(&rep)
	res.Body.Close()
	if !rep.OK || rep.Accepted != 0 || rep.Duplicates != 1 {
		t.Fatalf("replay resp=%+v", rep)
	}

	from := now.Add(-time.Hour).Format(time.RFC3339)
	to := now.Add(time.Hour).Format(time.RFC3339)
	req, _ = http.NewRequest(http.MethodGet, ts.URL+"/api/v1/usage/summary?from="+from+"&to="+to, nil)
	req.Header.Set("Authorization", "Bearer dev-secret")
	res, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	var sum apitypes.UsageSummaryResponse
	_ = json.NewDecoder(res.Body).Decode(&sum)
	res.Body.Close()
	if sum.InputTokens != 100 || sum.OutputTokens != 20 || sum.CacheHitTokens != 400 {
		t.Fatalf("sum=%+v", sum)
	}

	req, _ = http.NewRequest(http.MethodGet, ts.URL+"/api/v1/usage/breakdown?from="+from+"&to="+to+"&group_by=model", nil)
	req.Header.Set("Authorization", "Bearer dev-secret")
	res, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	var bd apitypes.UsageBreakdownResponse
	_ = json.NewDecoder(res.Body).Decode(&bd)
	res.Body.Close()
	if len(bd.Groups) != 1 || bd.Groups[0].Key != "claude-sonnet-4-5" {
		t.Fatalf("bd=%+v", bd)
	}
}
