package server

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gorilla/websocket"
	"github.com/ynlea/agent-status/internal/auth"
	"github.com/ynlea/agent-status/internal/store"
	"github.com/ynlea/agent-status/pkg/apitypes"
)

type Server struct {
	Key    string
	Store  store.Store
	Hub    *Hub
	Logger *slog.Logger
}

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

func (s *Server) log() *slog.Logger {
	if s.Logger != nil {
		return s.Logger
	}
	return slog.Default()
}

func (s *Server) Routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/api/v1/report", s.requireAuth(s.handleReport))
	mux.HandleFunc("/api/v1/usage/report", s.requireAuth(s.handleUsageReport))
	mux.HandleFunc("/api/v1/usage/summary", s.requireAuth(s.handleUsageSummary))
	mux.HandleFunc("/api/v1/usage/breakdown", s.requireAuth(s.handleUsageBreakdown))
	mux.HandleFunc("/api/v1/providers/report", s.requireAuth(s.handleProvidersReport))
	mux.HandleFunc("/api/v1/commands/pull", s.requireAuth(s.handleCommandsPull))
	mux.HandleFunc("/api/v1/commands/", s.requireAuth(s.handleCommandSub))
	mux.HandleFunc("/api/v1/machines", s.requireAuth(s.handleMachines))
	mux.HandleFunc("/api/v1/machines/", s.requireAuth(s.handleMachineSub))
	mux.HandleFunc("/api/v1/history", s.requireAuth(s.handleHistory))
	mux.HandleFunc("/api/v1/ws", s.handleWS)
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})
	return mux
}

func (s *Server) requireAuth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !auth.Check(r, s.Key) {
			s.log().Warn("鉴权失败", "请求路径", r.URL.Path)
			writeErr(w, http.StatusUnauthorized, "unauthorized", "invalid or missing key")
			return
		}
		next(w, r)
	}
}

func (s *Server) handleReport(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeErr(w, http.StatusMethodNotAllowed, "method_not_allowed", "POST required")
		return
	}
	var req apitypes.ReportRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeErr(w, http.StatusBadRequest, "bad_json", "invalid JSON body")
		return
	}
	if req.MachineID == "" {
		writeErr(w, http.StatusBadRequest, "invalid_request", "machine_id required")
		return
	}
	for _, sess := range req.Sessions {
		if sess.State != "" && !sess.State.Valid() {
			writeErr(w, http.StatusBadRequest, "invalid_state", "state must be confirm|working|done|idle")
			return
		}
	}

	changed, wasOnline := s.Store.ApplyReport(req)
	if !wasOnline {
		s.log().Info("设备上线",
			"设备标识", req.MachineID,
			"设备名称", req.MachineName,
			"平台", req.Platform,
			"会话数", len(req.Sessions),
		)
		s.Hub.Broadcast(apitypes.WSEvent{
			Type: apitypes.WSMachineOnline,
			Payload: apitypes.Machine{
				MachineID:   req.MachineID,
				MachineName: req.MachineName,
				Platform:    req.Platform,
				Online:      true,
				LastSeenAt:  time.Now().UTC(),
			},
		})
	}
	for _, sess := range changed {
		// Only log real session changes (new or state transition); quiet heartbeats stay silent.
		s.log().Info("会话状态已更新",
			"设备标识", req.MachineID,
			"设备名称", req.MachineName,
			"来源", sess.Source,
			"代理", sess.Agent,
			"会话标识", sess.SessionID,
			"显示名称", sess.DisplayName,
			"状态", sess.State,
			"颜色", sess.State.Color(),
			"说明", sess.Message,
		)
		s.Hub.Broadcast(apitypes.WSEvent{Type: apitypes.WSSessionUpsert, Payload: sess})
		s.Hub.Broadcast(apitypes.WSEvent{
			Type: apitypes.WSNotification,
			Payload: apitypes.NotificationPayload{
				MachineID:   sess.MachineID,
				MachineName: sess.MachineName,
				Agent:       sess.Agent,
				SessionID:   sess.SessionID,
				DisplayName: sess.DisplayName,
				State:       sess.State,
				Color:       sess.State.Color(),
				Message:     sess.Message,
				At:          sess.UpdatedAt,
			},
		})
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"ok":      true,
		"changed": len(changed),
	})
}

func (s *Server) handleMachines(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeErr(w, http.StatusMethodNotAllowed, "method_not_allowed", "GET required")
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"machines": s.Store.ListMachines(),
	})
}

func (s *Server) handleMachineSub(w http.ResponseWriter, r *http.Request) {
	path := strings.TrimPrefix(r.URL.Path, "/api/v1/machines/")
	parts := strings.Split(strings.Trim(path, "/"), "/")
	if len(parts) == 0 || parts[0] == "" {
		writeErr(w, http.StatusNotFound, "not_found", "machine id required")
		return
	}
	machineID := parts[0]

	// PATCH /api/v1/machines/{id}  body: {"machine_name":"..."}
	if len(parts) == 1 && r.Method == http.MethodPatch {
		var body struct {
			MachineName string `json:"machine_name"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			writeErr(w, http.StatusBadRequest, "bad_json", "invalid JSON body")
			return
		}
		m, err := s.Store.RenameMachine(machineID, body.MachineName)
		if err != nil {
			if strings.Contains(err.Error(), "not found") {
				writeErr(w, http.StatusNotFound, "not_found", err.Error())
				return
			}
			writeErr(w, http.StatusBadRequest, "invalid_request", err.Error())
			return
		}
		writeJSON(w, http.StatusOK, map[string]interface{}{"machine": m})
		return
	}

	// GET /api/v1/machines/{id}/providers
	if len(parts) == 2 && parts[1] == "providers" {
		if r.Method != http.MethodGet {
			writeErr(w, http.StatusMethodNotAllowed, "method_not_allowed", "GET required")
			return
		}
		app := r.URL.Query().Get("app")
		if app == "" {
			app = "all"
		}
		resp, err := s.Store.ListProviders(machineID, app)
		if err != nil {
			writeErr(w, http.StatusBadRequest, "invalid_request", err.Error())
			return
		}
		writeJSON(w, http.StatusOK, resp)
		return
	}

	// POST /api/v1/machines/{id}/commands
	if len(parts) == 2 && parts[1] == "commands" {
		if r.Method != http.MethodPost {
			writeErr(w, http.StatusMethodNotAllowed, "method_not_allowed", "POST required")
			return
		}
		var req apitypes.EnqueueCommandRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeErr(w, http.StatusBadRequest, "bad_json", "invalid JSON body")
			return
		}
		cmd, err := s.Store.EnqueueCommand(machineID, req)
		if err != nil {
			writeErr(w, http.StatusBadRequest, "invalid_request", err.Error())
			return
		}
		s.log().Info("命令已入队",
			"设备标识", machineID,
			"命令标识", cmd.ID,
			"应用", cmd.App,
			"类型", cmd.Type,
		)
		writeJSON(w, http.StatusOK, apitypes.EnqueueCommandResponse{
			CommandID: cmd.ID,
			Status:    cmd.Status,
		})
		return
	}

	// GET /api/v1/machines/{id}/sessions
	if r.Method != http.MethodGet {
		writeErr(w, http.StatusMethodNotAllowed, "method_not_allowed", "GET or PATCH required")
		return
	}
	if len(parts) != 2 || parts[1] != "sessions" {
		writeErr(w, http.StatusNotFound, "not_found", "use /api/v1/machines/{id}/sessions|providers|commands or PATCH /api/v1/machines/{id}")
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"machine_id": machineID,
		"sessions":   s.Store.ListSessions(machineID),
	})
}

func (s *Server) handleProvidersReport(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeErr(w, http.StatusMethodNotAllowed, "method_not_allowed", "POST required")
		return
	}
	var req apitypes.ProvidersReportRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeErr(w, http.StatusBadRequest, "bad_json", "invalid JSON body")
		return
	}
	if err := s.Store.ApplyProvidersReport(req); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid_request", err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"ok": true})
}

func (s *Server) handleCommandsPull(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeErr(w, http.StatusMethodNotAllowed, "method_not_allowed", "POST required")
		return
	}
	var req apitypes.CommandsPullRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeErr(w, http.StatusBadRequest, "bad_json", "invalid JSON body")
		return
	}
	cmds, err := s.Store.PullCommands(req.MachineID, req.Limit)
	if err != nil {
		writeErr(w, http.StatusBadRequest, "invalid_request", err.Error())
		return
	}
	if cmds == nil {
		cmds = []apitypes.MachineCommand{}
	}
	writeJSON(w, http.StatusOK, apitypes.CommandsPullResponse{Commands: cmds})
}

func (s *Server) handleCommandSub(w http.ResponseWriter, r *http.Request) {
	path := strings.TrimPrefix(r.URL.Path, "/api/v1/commands/")
	parts := strings.Split(strings.Trim(path, "/"), "/")
	if len(parts) == 0 || parts[0] == "" {
		writeErr(w, http.StatusNotFound, "not_found", "command id required")
		return
	}
	id := parts[0]

	// POST /api/v1/commands/{id}/result
	if len(parts) == 2 && parts[1] == "result" {
		if r.Method != http.MethodPost {
			writeErr(w, http.StatusMethodNotAllowed, "method_not_allowed", "POST required")
			return
		}
		var req apitypes.CommandResultRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeErr(w, http.StatusBadRequest, "bad_json", "invalid JSON body")
			return
		}
		cmd, err := s.Store.CompleteCommand(id, req)
		if err != nil {
			if strings.Contains(err.Error(), "not found") {
				writeErr(w, http.StatusNotFound, "not_found", err.Error())
				return
			}
			writeErr(w, http.StatusBadRequest, "invalid_request", err.Error())
			return
		}
		cmd.Payload.APIKey = ""
		s.log().Info("命令已完成",
			"命令标识", cmd.ID,
			"设备标识", cmd.MachineID,
			"状态", cmd.Status,
			"错误摘要", cmd.ErrorMessage,
		)
		writeJSON(w, http.StatusOK, map[string]interface{}{"ok": true, "command": cmd})
		return
	}

	// GET /api/v1/commands/{id}
	if len(parts) == 1 {
		if r.Method != http.MethodGet {
			writeErr(w, http.StatusMethodNotAllowed, "method_not_allowed", "GET required")
			return
		}
		cmd, err := s.Store.GetCommand(id)
		if err != nil {
			writeErr(w, http.StatusNotFound, "not_found", err.Error())
			return
		}
		cmd.Payload.APIKey = ""
		writeJSON(w, http.StatusOK, cmd)
		return
	}

	writeErr(w, http.StatusNotFound, "not_found", "use GET /api/v1/commands/{id} or POST .../result")
}

func (s *Server) handleUsageReport(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeErr(w, http.StatusMethodNotAllowed, "method_not_allowed", "POST required")
		return
	}
	var req apitypes.UsageReportRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeErr(w, http.StatusBadRequest, "bad_json", "invalid JSON body")
		return
	}
	if req.MachineID == "" {
		writeErr(w, http.StatusBadRequest, "invalid_request", "machine_id required")
		return
	}
	if len(req.Events) > 2000 {
		writeErr(w, http.StatusBadRequest, "invalid_request", "events batch too large (max 2000)")
		return
	}
	accepted, duplicates := s.Store.ApplyUsageReport(req)
	s.log().Info("用量上报",
		"设备标识", req.MachineID,
		"接收", accepted,
		"重复", duplicates,
		"批次", len(req.Events),
	)
	writeJSON(w, http.StatusOK, apitypes.UsageReportResponse{
		OK:         true,
		Accepted:   accepted,
		Duplicates: duplicates,
	})
}

func (s *Server) parseUsageQuery(r *http.Request) (apitypes.UsageQuery, string) {
	q := apitypes.UsageQuery{
		MachineID: r.URL.Query().Get("machine_id"),
		Agent:     r.URL.Query().Get("agent"),
		Model:     r.URL.Query().Get("model"),
		GroupBy:   r.URL.Query().Get("group_by"),
	}
	if from := r.URL.Query().Get("from"); from != "" {
		t, err := time.Parse(time.RFC3339, from)
		if err != nil {
			t, err = time.Parse(time.RFC3339Nano, from)
		}
		if err != nil {
			return q, "invalid from (use RFC3339)"
		}
		q.From = t.UTC()
	}
	if to := r.URL.Query().Get("to"); to != "" {
		t, err := time.Parse(time.RFC3339, to)
		if err != nil {
			t, err = time.Parse(time.RFC3339Nano, to)
		}
		if err != nil {
			return q, "invalid to (use RFC3339)"
		}
		q.To = t.UTC()
	}
	if q.From.IsZero() && q.To.IsZero() {
		// default: last 24h
		now := time.Now().UTC()
		q.To = now
		q.From = now.Add(-24 * time.Hour)
	}
	return q, ""
}

func (s *Server) handleUsageSummary(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeErr(w, http.StatusMethodNotAllowed, "method_not_allowed", "GET required")
		return
	}
	q, errMsg := s.parseUsageQuery(r)
	if errMsg != "" {
		writeErr(w, http.StatusBadRequest, "invalid_query", errMsg)
		return
	}
	writeJSON(w, http.StatusOK, s.Store.UsageSummary(q))
}

func (s *Server) handleUsageBreakdown(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeErr(w, http.StatusMethodNotAllowed, "method_not_allowed", "GET required")
		return
	}
	q, errMsg := s.parseUsageQuery(r)
	if errMsg != "" {
		writeErr(w, http.StatusBadRequest, "invalid_query", errMsg)
		return
	}
	writeJSON(w, http.StatusOK, s.Store.UsageBreakdown(q))
}

func (s *Server) handleHistory(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeErr(w, http.StatusMethodNotAllowed, "method_not_allowed", "GET required")
		return
	}
	limit := 50
	if q := r.URL.Query().Get("limit"); q != "" {
		if n, err := strconv.Atoi(q); err == nil && n > 0 {
			limit = n
		}
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"history": s.Store.ListHistory(limit),
	})
}

func (s *Server) handleWS(w http.ResponseWriter, r *http.Request) {
	if !auth.Check(r, s.Key) {
		writeErr(w, http.StatusUnauthorized, "unauthorized", "invalid or missing key")
		return
	}
	c, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}
	s.Hub.Add(c)
	defer s.Hub.Remove(c)
	for {
		if _, _, err := c.ReadMessage(); err != nil {
			return
		}
	}
}

// RunCleanupLoop periodically cleans history and marks stale machines offline.
func (s *Server) RunCleanupLoop(stop <-chan struct{}, every time.Duration, historyTTLSec int64, historyMax int, machineOfflineSec int64) {
	if every <= 0 {
		every = time.Minute
	}
	t := time.NewTicker(every)
	defer t.Stop()
	for {
		select {
		case <-stop:
			return
		case <-t.C:
			del, off := s.Store.Cleanup(historyTTLSec, historyMax, machineOfflineSec)
			if del > 0 || off > 0 {
				s.log().Info("历史记录清理完成", "删除记录数", del, "离线设备数", off)
			}
		}
	}
}

func writeJSON(w http.ResponseWriter, status int, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeErr(w http.ResponseWriter, status int, code, msg string) {
	writeJSON(w, status, apitypes.ErrorBody{
		Error: apitypes.ErrorDetail{Code: code, Message: msg},
	})
}
