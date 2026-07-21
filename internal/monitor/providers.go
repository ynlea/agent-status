package monitor

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"github.com/ynlea/agent-status/internal/monitor/ccswitch"
	"github.com/ynlea/agent-status/pkg/apitypes"
)

// NewCcSwitchAdapter builds the local adapter from monitor config.
func NewCcSwitchAdapter(cfg *Config) *ccswitch.Adapter {
	if cfg == nil {
		return ccswitch.NewAdapter("", "")
	}
	return ccswitch.NewAdapter(cfg.CcSwitchDB, cfg.CcSwitchBin)
}

// ReportProviders posts a redacted provider snapshot (legacy helper).
func (r *Reporter) ReportProviders(apps []apitypes.ProviderAppSnapshot) error {
	return r.ReportProvidersRequest(apitypes.ProvidersReportRequest{
		MachineID:   r.Cfg.MachineID,
		MachineName: r.Cfg.MachineName,
		Platform:    r.platform(),
		ReportedAt:  time.Now().UTC(),
		Apps:        apps,
	})
}

// ReportProvidersRequest posts a full providers report including readiness flags.
func (r *Reporter) ReportProvidersRequest(req apitypes.ProvidersReportRequest) error {
	if req.ReportedAt.IsZero() {
		req.ReportedAt = time.Now().UTC()
	}
	if req.MachineID == "" {
		req.MachineID = r.Cfg.MachineID
	}
	if req.MachineName == "" {
		req.MachineName = r.Cfg.MachineName
	}
	if req.Platform == "" {
		req.Platform = r.platform()
	}
	return r.postJSON("/api/v1/providers/report", req)
}

// PullCommands leases pending commands for this machine.
func (r *Reporter) PullCommands(limit int) ([]apitypes.MachineCommand, error) {
	if limit <= 0 {
		limit = 1
	}
	req := apitypes.CommandsPullRequest{
		MachineID: r.Cfg.MachineID,
		Limit:     limit,
	}
	var resp apitypes.CommandsPullResponse
	if err := r.postJSONDecode("/api/v1/commands/pull", req, &resp); err != nil {
		return nil, err
	}
	if resp.Commands == nil {
		return []apitypes.MachineCommand{}, nil
	}
	return resp.Commands, nil
}

// CompleteCommand reports command outcome, optionally attaching a fresh snapshot.
func (r *Reporter) CompleteCommand(id string, status, errMsg string, report *apitypes.ProvidersReportRequest) error {
	req := apitypes.CommandResultRequest{
		MachineID:    r.Cfg.MachineID,
		Status:       status,
		ErrorMessage: errMsg,
	}
	if report != nil {
		if report.ReportedAt.IsZero() {
			report.ReportedAt = time.Now().UTC()
		}
		if report.MachineID == "" {
			report.MachineID = r.Cfg.MachineID
		}
		if report.MachineName == "" {
			report.MachineName = r.Cfg.MachineName
		}
		if report.Platform == "" {
			report.Platform = r.platform()
		}
		req.ProvidersReport = report
	}
	return r.postJSON("/api/v1/commands/"+id+"/result", req)
}

func (r *Reporter) postJSONDecode(path string, payload, out interface{}) error {
	raw, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	base, err := r.baseURL()
	if err != nil {
		return err
	}
	httpReq, err := http.NewRequest(http.MethodPost, base+path, bytes.NewReader(raw))
	if err != nil {
		return err
	}
	httpReq.Header.Set("Authorization", "Bearer "+r.Cfg.Key)
	httpReq.Header.Set("Content-Type", "application/json")
	res, err := r.Client.Do(httpReq)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(res.Body, 1<<20))
	if res.StatusCode >= 300 {
		return fmt.Errorf("%s status %d: %s", path, res.StatusCode, string(body))
	}
	if out == nil {
		return nil
	}
	return json.Unmarshal(body, out)
}

// ProviderController periodically reports providers and executes remote commands.
type ProviderController struct {
	Cfg     *Config
	Rep     *Reporter
	Adapter *ccswitch.Adapter
	Logger  *slog.Logger

	runMu sync.Mutex // serialize command execution across WS + poll
}

func (p *ProviderController) log() *slog.Logger {
	if p.Logger != nil {
		return p.Logger
	}
	return slog.Default()
}

// RunLoop reports provider snapshots periodically.
// When command_poll_sec > 0, also pulls and executes remote commands.
// command_poll_sec == 0 disables command execution only (snapshots still report).
func (p *ProviderController) RunLoop(stop <-chan struct{}) {
	if p == nil || p.Cfg == nil || p.Rep == nil {
		return
	}
	pollSec := p.Cfg.CommandPollSec
	reportSec := p.Cfg.ProviderReportSec
	if reportSec <= 0 {
		reportSec = p.Cfg.ReportIntervalSec
	}
	if reportSec <= 0 {
		reportSec = 60
	}

	reportT := time.NewTicker(time.Duration(reportSec) * time.Second)
	defer reportT.Stop()

	var pollC <-chan time.Time
	var pollT *time.Ticker
	if pollSec > 0 {
		pollT = time.NewTicker(time.Duration(pollSec) * time.Second)
		pollC = pollT.C
		defer pollT.Stop()
	}

	// initial snapshot
	p.reportOnce("startup")

	// Long-lived command channel (sub-second wakeups); poll remains a safety net.
	go p.runCommandWS(stop)

	for {
		select {
		case <-stop:
			return
		case <-pollC:
			p.pullAndRun()
		case <-reportT.C:
			p.reportOnce("interval")
		}
	}
}

func (p *ProviderController) reportOnce(reason string) {
	if p.Adapter == nil {
		return
	}
	req := apitypes.ProvidersReportRequest{
		MachineID:         p.Cfg.MachineID,
		MachineName:       p.Cfg.MachineName,
		Platform:          p.Rep.platform(),
		ReportedAt:        time.Now().UTC(),
		Apps:              []apitypes.ProviderAppSnapshot{},
		CcSwitchAvailable: p.Adapter.Available(),
		CcSwitchCLIReady:  p.Adapter.CLIReady(),
		CcSwitchBin:       p.Adapter.ResolvedBin(),
	}
	if p.Adapter.Available() {
		apps, err := p.Adapter.ListApps()
		if err != nil {
			p.log().Warn("采集 cc-switch 供应商失败", "原因", reason, "错误", err)
		} else {
			req.Apps = apps
		}
	}
	if err := p.Rep.ReportProvidersRequest(req); err != nil {
		p.log().Warn("上报供应商快照失败", "原因", reason, "错误", err)
	}
}

func (p *ProviderController) pullAndRun() {
	p.runMu.Lock()
	defer p.runMu.Unlock()
	if p.Adapter == nil || p.Rep == nil {
		return
	}
	// still poll even if db missing so failed commands can surface
	cmds, err := p.Rep.PullCommands(1)
	if err != nil {
		p.log().Warn("拉取远程命令失败", "错误", err)
		return
	}
	for _, cmd := range cmds {
		p.runOne(cmd)
	}
}

func (p *ProviderController) runCommandWS(stop <-chan struct{}) {
	backoff := time.Second
	for {
		select {
		case <-stop:
			return
		default:
		}
		err := p.commandWSSession(stop)
		if err != nil {
			p.log().Warn("命令通道会话结束", "错误", err)
		}
		select {
		case <-stop:
			return
		case <-time.After(backoff):
		}
		if backoff < 15*time.Second {
			backoff *= 2
			if backoff > 15*time.Second {
				backoff = 15 * time.Second
			}
		}
	}
}

func (p *ProviderController) commandWSSession(stop <-chan struct{}) error {
	if p.Rep == nil || p.Cfg == nil {
		return fmt.Errorf("reporter not configured")
	}
	base, err := p.Rep.baseURL()
	if err != nil {
		return err
	}
	wsBase := base
	if strings.HasPrefix(wsBase, "https://") {
		wsBase = "wss://" + strings.TrimPrefix(wsBase, "https://")
	} else if strings.HasPrefix(wsBase, "http://") {
		wsBase = "ws://" + strings.TrimPrefix(wsBase, "http://")
	} else {
		return fmt.Errorf("unsupported server_url scheme")
	}
	u, err := url.Parse(wsBase + "/api/v1/monitor/ws")
	if err != nil {
		return err
	}
	q := u.Query()
	q.Set("machine_id", p.Cfg.MachineID)
	u.RawQuery = q.Encode()

	hdr := http.Header{}
	hdr.Set("Authorization", "Bearer "+p.Cfg.Key)
	hdr.Set("X-Agent-Status-Key", p.Cfg.Key)

	dialer := websocket.Dialer{HandshakeTimeout: 15 * time.Second}
	conn, resp, err := dialer.Dial(u.String(), hdr)
	if err != nil {
		if resp != nil {
			return fmt.Errorf("ws dial: %w (status %d)", err, resp.StatusCode)
		}
		return fmt.Errorf("ws dial: %w", err)
	}
	defer conn.Close()
	p.log().Info("已连接服务端命令通道", "地址", u.String())

	// Drain any backlog immediately.
	p.pullAndRun()

	// Reset backoff is done by returning nil only on stop; session errors reconnect.
	done := make(chan struct{})
	go func() {
		ticker := time.NewTicker(25 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-stop:
				_ = conn.Close()
				return
			case <-done:
				return
			case <-ticker.C:
				_ = conn.WriteControl(websocket.PingMessage, []byte("ping"), time.Now().Add(5*time.Second))
			}
		}
	}()
	defer close(done)

	_ = conn.SetReadDeadline(time.Now().Add(90 * time.Second))
	conn.SetPongHandler(func(string) error {
		_ = conn.SetReadDeadline(time.Now().Add(90 * time.Second))
		return nil
	})

	for {
		select {
		case <-stop:
			return nil
		default:
		}
		_, data, err := conn.ReadMessage()
		if err != nil {
			return err
		}
		_ = conn.SetReadDeadline(time.Now().Add(90 * time.Second))
		var ev struct {
			Type string `json:"type"`
		}
		if err := json.Unmarshal(data, &ev); err != nil {
			continue
		}
		switch ev.Type {
		case apitypes.WSCommandAvailable, apitypes.WSMonitorCommand:
			p.pullAndRun()
		default:
			// ignore unknown
		}
	}
}

func (p *ProviderController) runOne(cmd apitypes.MachineCommand) {
	p.log().Info("开始执行远程命令",
		"命令标识", cmd.ID,
		"应用", cmd.App,
		"类型", cmd.Type,
		"供应商", cmd.Payload.ProviderID,
	)
	var execErr error
	if p.Adapter == nil {
		execErr = fmt.Errorf("cc-switch adapter not configured")
	} else if cmd.Type != apitypes.CommandTypeRefreshProviders && !p.Adapter.CLIReady() {
		execErr = fmt.Errorf("cc-switch-cli not installed or not found")
	} else if !p.Adapter.Available() && cmd.Type != apitypes.CommandTypeRefreshProviders {
		execErr = fmt.Errorf("cc-switch database not found")
	} else if cmd.Type == apitypes.CommandTypeRefreshProviders && !p.Adapter.Available() {
		execErr = fmt.Errorf("cc-switch database not found")
	} else {
		execErr = p.Adapter.Execute(cmd)
	}

	status := apitypes.CommandStatusSucceeded
	errMsg := ""
	var report *apitypes.ProvidersReportRequest
	if execErr != nil {
		status = apitypes.CommandStatusFailed
		errMsg = execErr.Error()
		if len(errMsg) > 400 {
			errMsg = errMsg[:400]
		}
		p.log().Warn("远程命令执行失败", "命令标识", cmd.ID, "错误", errMsg)
	} else {
		p.log().Info("远程命令执行成功", "命令标识", cmd.ID)
	}
	// Always attach latest readiness/snapshot after command attempt.
	if p.Adapter != nil {
		rep := &apitypes.ProvidersReportRequest{
			MachineID:         p.Cfg.MachineID,
			MachineName:       p.Cfg.MachineName,
			Platform:          p.Rep.platform(),
			ReportedAt:        time.Now().UTC(),
			Apps:              []apitypes.ProviderAppSnapshot{},
			CcSwitchAvailable: p.Adapter.Available(),
			CcSwitchCLIReady:  p.Adapter.CLIReady(),
			CcSwitchBin:       p.Adapter.ResolvedBin(),
		}
		if p.Adapter.Available() {
			if listed, err := p.Adapter.ListApps(); err == nil {
				rep.Apps = listed
			}
		}
		report = rep
	}
	if err := p.Rep.CompleteCommand(cmd.ID, status, errMsg, report); err != nil {
		p.log().Warn("回报命令结果失败", "命令标识", cmd.ID, "错误", err)
	}
}
