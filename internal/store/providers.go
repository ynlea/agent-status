package store

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"strings"
	"time"

	"github.com/ynlea/agent-status/pkg/apitypes"
)

// Default command timeouts (seconds).
const (
	CommandQueuedTimeoutSec  = 120
	CommandRunningTimeoutSec = 60
	CommandLeaseSec          = 60
)

func newCommandID() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		return fmt.Sprintf("cmd-%d", time.Now().UnixNano())
	}
	return "cmd-" + hex.EncodeToString(b[:])
}

func stripAPIKey(p apitypes.CommandPayload) apitypes.CommandPayload {
	p.APIKey = ""
	return p
}

func validateEnqueue(machineID string, req apitypes.EnqueueCommandRequest) error {
	if strings.TrimSpace(machineID) == "" {
		return fmt.Errorf("machine_id required")
	}
	if !apitypes.ValidCommandType(req.Type) {
		return fmt.Errorf("unsupported command type")
	}
	switch req.Type {
	case apitypes.CommandTypeRefreshProviders:
		app := strings.TrimSpace(req.App)
		if app == "" || app == apitypes.ProviderAppAll {
			return nil
		}
		if !apitypes.ValidProviderApp(app) {
			return fmt.Errorf("app must be codex|claude|all")
		}
		return nil
	case apitypes.CommandTypeCreateProvider:
		if !apitypes.ValidProviderApp(req.App) {
			return fmt.Errorf("app must be codex|claude")
		}
		if strings.TrimSpace(req.Payload.Name) == "" {
			return fmt.Errorf("payload.name required")
		}
		return nil
	case apitypes.CommandTypeDeleteProvider, apitypes.CommandTypeDuplicateProvider,
		apitypes.CommandTypeSwitchProvider, apitypes.CommandTypeUpdateProvider:
		if !apitypes.ValidProviderApp(req.App) {
			return fmt.Errorf("app must be codex|claude")
		}
		if strings.TrimSpace(req.Payload.ProviderID) == "" {
			return fmt.Errorf("payload.provider_id required")
		}
		return nil
	default:
		return fmt.Errorf("unsupported command type")
	}
}

func sanitizeResultStatus(status string) (string, error) {
	switch status {
	case apitypes.CommandStatusSucceeded, apitypes.CommandStatusFailed:
		return status, nil
	default:
		return "", fmt.Errorf("status must be succeeded|failed")
	}
}
