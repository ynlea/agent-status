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

func (r *Reporter) Report(sessions []apitypes.Session) error {
	reqBody := apitypes.ReportRequest{
		MachineID:   r.Cfg.MachineID,
		MachineName: r.Cfg.MachineName,
		Platform:    r.platform(),
		Sessions:    sessions,
		ReportedAt:  time.Now().UTC(),
	}
	raw, err := json.Marshal(reqBody)
	if err != nil {
		return err
	}
	url := r.Cfg.ServerURL
	if url == "" {
		return fmt.Errorf("empty server_url")
	}
	// trim trailing slash
	for len(url) > 0 && url[len(url)-1] == '/' {
		url = url[:len(url)-1]
	}
	httpReq, err := http.NewRequest(http.MethodPost, url+"/api/v1/report", bytes.NewReader(raw))
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
	body, _ := io.ReadAll(io.LimitReader(res.Body, 4096))
	if res.StatusCode >= 300 {
		return fmt.Errorf("report status %d: %s", res.StatusCode, string(body))
	}
	return nil
}
