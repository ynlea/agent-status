package monitor

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"runtime"
	"time"

	"github.com/ynlea/agent-status/pkg/apitypes"
)

type Reporter struct {
	Client *http.Client
	Cfg    *Config
}

func NewReporter(cfg *Config) *Reporter {
	return &Reporter{
		Client: &http.Client{Timeout: 15 * time.Second},
		Cfg:    cfg,
	}
}

func (r *Reporter) platform() string {
	if r.Cfg.Platform != "" {
		return r.Cfg.Platform
	}
	switch runtime.GOOS {
	case "windows":
		return "windows"
	default:
		return "linux"
	}
}

func (r *Reporter) baseURL() (string, error) {
	url := r.Cfg.ServerURL
	if url == "" {
		return "", fmt.Errorf("empty server_url")
	}
	for len(url) > 0 && url[len(url)-1] == '/' {
		url = url[:len(url)-1]
	}
	return url, nil
}

func (r *Reporter) postJSON(path string, payload interface{}) error {
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
	// usage backfill batches can be slower
	client := r.Client
	if path == "/api/v1/usage/report" {
		client = &http.Client{Timeout: 60 * time.Second}
	}
	res, err := client.Do(httpReq)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(res.Body, 4096))
	if res.StatusCode >= 300 {
		return fmt.Errorf("%s status %d: %s", path, res.StatusCode, string(body))
	}
	return nil
}

func (r *Reporter) Report(sessions []apitypes.Session) error {
	reqBody := apitypes.ReportRequest{
		MachineID:   r.Cfg.MachineID,
		MachineName: r.Cfg.MachineName,
		Platform:    r.platform(),
		Sessions:    sessions,
		ReportedAt:  time.Now().UTC(),
	}
	return r.postJSON("/api/v1/report", reqBody)
}

// ReportUsage posts a batch of usage events.
func (r *Reporter) ReportUsage(events []apitypes.UsageEvent) error {
	if len(events) == 0 {
		return nil
	}
	reqBody := apitypes.UsageReportRequest{
		MachineID:   r.Cfg.MachineID,
		MachineName: r.Cfg.MachineName,
		Platform:    r.platform(),
		ReportedAt:  time.Now().UTC(),
		Events:      events,
	}
	return r.postJSON("/api/v1/usage/report", reqBody)
}
