package server

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
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

func TestProvidersAndCommandsHTTP(t *testing.T) {
	srv := &Server{
		Key:   "dev-secret",
		Store: store.NewMemory(20),
		Hub:   NewHub(),
	}
	ts := httptest.NewServer(srv.Routes())
	defer ts.Close()

	auth := func(req *http.Request) {
		req.Header.Set("Authorization", "Bearer dev-secret")
		req.Header.Set("Content-Type", "application/json")
	}

	// unauthorized
	res, err := http.Post(ts.URL+"/api/v1/providers/report", "application/json", bytes.NewReader([]byte(`{}`)))
	if err != nil {
		t.Fatal(err)
	}
	res.Body.Close()
	if res.StatusCode != http.StatusUnauthorized {
		t.Fatalf("unauth status=%d", res.StatusCode)
	}

	// report providers
	body := map[string]interface{}{
		"machine_id": "m1",
		"apps": []map[string]interface{}{{
			"app": "codex", "current_id": "p1",
			"providers": []map[string]interface{}{{
				"id": "p1", "name": "one", "has_api_key": true,
			}},
		}},
	}
	raw, _ := json.Marshal(body)
	req, _ := http.NewRequest(http.MethodPost, ts.URL+"/api/v1/providers/report", bytes.NewReader(raw))
	auth(req)
	res, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	res.Body.Close()
	if res.StatusCode != http.StatusOK {
		t.Fatalf("report status=%d", res.StatusCode)
	}

	req, _ = http.NewRequest(http.MethodGet, ts.URL+"/api/v1/machines/m1/providers?app=codex", nil)
	auth(req)
	res, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	var list apitypes.ProvidersListResponse
	_ = json.NewDecoder(res.Body).Decode(&list)
	res.Body.Close()
	if len(list.Apps) != 1 || list.Apps[0].CurrentID != "p1" {
		t.Fatalf("list=%+v", list)
	}

	// enqueue
	raw, _ = json.Marshal(map[string]interface{}{
		"app": "codex", "type": "switch_provider",
		"payload": map[string]string{"provider_id": "p1", "api_key": "secret"},
	})
	req, _ = http.NewRequest(http.MethodPost, ts.URL+"/api/v1/machines/m1/commands", bytes.NewReader(raw))
	auth(req)
	res, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	var enq apitypes.EnqueueCommandResponse
	_ = json.NewDecoder(res.Body).Decode(&enq)
	res.Body.Close()
	if enq.CommandID == "" || enq.Status != "queued" {
		t.Fatalf("enq=%+v", enq)
	}

	// pull
	raw, _ = json.Marshal(map[string]interface{}{"machine_id": "m1", "limit": 1})
	req, _ = http.NewRequest(http.MethodPost, ts.URL+"/api/v1/commands/pull", bytes.NewReader(raw))
	auth(req)
	res, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	var pull apitypes.CommandsPullResponse
	_ = json.NewDecoder(res.Body).Decode(&pull)
	res.Body.Close()
	if len(pull.Commands) != 1 || pull.Commands[0].Status != "running" {
		t.Fatalf("pull=%+v", pull)
	}

	// result
	raw, _ = json.Marshal(map[string]interface{}{
		"machine_id": "m1", "status": "succeeded",
	})
	req, _ = http.NewRequest(http.MethodPost, ts.URL+"/api/v1/commands/"+enq.CommandID+"/result", bytes.NewReader(raw))
	auth(req)
	res, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	res.Body.Close()
	if res.StatusCode != http.StatusOK {
		t.Fatalf("result status=%d", res.StatusCode)
	}

	req, _ = http.NewRequest(http.MethodGet, ts.URL+"/api/v1/commands/"+enq.CommandID, nil)
	auth(req)
	res, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	var cmd apitypes.MachineCommand
	_ = json.NewDecoder(res.Body).Decode(&cmd)
	res.Body.Close()
	if cmd.Status != "succeeded" || cmd.Payload.APIKey != "" {
		t.Fatalf("cmd=%+v", cmd)
	}
}

func TestMonitorWSCommandNotify(t *testing.T) {
	mem := store.NewMemory(20)
	srv := &Server{Key: "k", Store: mem, Hub: NewHub()}
	ts := httptest.NewServer(srv.Routes())
	defer ts.Close()

	// Connect monitor WS
	u := "ws" + strings.TrimPrefix(ts.URL, "http") + "/api/v1/monitor/ws?machine_id=m1"
	hdr := http.Header{}
	hdr.Set("Authorization", "Bearer k")
	conn, _, err := websocket.DefaultDialer.Dial(u, hdr)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()

	// Enqueue command
	body := `{"app":"codex","type":"refresh_providers","payload":{}}`
	req, _ := http.NewRequest(http.MethodPost, ts.URL+"/api/v1/machines/m1/commands", strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer k")
	req.Header.Set("Content-Type", "application/json")
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	res.Body.Close()
	if res.StatusCode != 200 {
		t.Fatalf("status %d", res.StatusCode)
	}

	_ = conn.SetReadDeadline(time.Now().Add(3 * time.Second))
	_, data, err := conn.ReadMessage()
	if err != nil {
		t.Fatalf("expected push: %v", err)
	}
	if !strings.Contains(string(data), "command_available") {
		t.Fatalf("unexpected payload %s", data)
	}
}
