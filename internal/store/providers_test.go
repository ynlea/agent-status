package store

import (
	"path/filepath"
	"testing"
	"time"

	"github.com/ynlea/agent-status/pkg/apitypes"
)

func TestMemoryCommandQueueSerialAndSnapshot(t *testing.T) {
	m := NewMemory(20)
	report := apitypes.ProvidersReportRequest{
		MachineID:  "m1",
		ReportedAt: time.Now().UTC(),
		Apps: []apitypes.ProviderAppSnapshot{{
			App:       "codex",
			CurrentID: "p1",
			Providers: []apitypes.ProviderInfo{{
				ID: "p1", Name: "one", HasAPIKey: true,
			}},
		}},
	}
	if err := m.ApplyProvidersReport(report); err != nil {
		t.Fatal(err)
	}
	list, err := m.ListProviders("m1", "codex")
	if err != nil {
		t.Fatal(err)
	}
	if len(list.Apps) != 1 || list.Apps[0].CurrentID != "p1" {
		t.Fatalf("list=%+v", list)
	}

	// replace snapshot
	report.Apps[0].CurrentID = "p2"
	report.Apps[0].Providers = []apitypes.ProviderInfo{{ID: "p2", Name: "two"}}
	if err := m.ApplyProvidersReport(report); err != nil {
		t.Fatal(err)
	}
	list, _ = m.ListProviders("m1", "all")
	if list.Apps[0].CurrentID != "p2" || len(list.Apps[0].Providers) != 1 {
		t.Fatalf("replace failed: %+v", list)
	}

	c1, err := m.EnqueueCommand("m1", apitypes.EnqueueCommandRequest{
		App:  "codex",
		Type: apitypes.CommandTypeSwitchProvider,
		Payload: apitypes.CommandPayload{
			ProviderID: "p2",
			APIKey:     "secret-should-strip",
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	c2, err := m.EnqueueCommand("m1", apitypes.EnqueueCommandRequest{
		App:     "codex",
		Type:    apitypes.CommandTypeSwitchProvider,
		Payload: apitypes.CommandPayload{ProviderID: "p1"},
	})
	if err != nil {
		t.Fatal(err)
	}

	pulled, err := m.PullCommands("m1", 1)
	if err != nil {
		t.Fatal(err)
	}
	if len(pulled) != 1 || pulled[0].ID != c1.ID || pulled[0].Status != apitypes.CommandStatusRunning {
		t.Fatalf("pull1=%+v", pulled)
	}
	// serial: second pull empty while first running
	pulled2, err := m.PullCommands("m1", 1)
	if err != nil || len(pulled2) != 0 {
		t.Fatalf("expected empty while running, got %+v err=%v", pulled2, err)
	}

	done, err := m.CompleteCommand(c1.ID, apitypes.CommandResultRequest{
		MachineID: "m1",
		Status:    apitypes.CommandStatusSucceeded,
	})
	if err != nil {
		t.Fatal(err)
	}
	if done.Payload.APIKey != "" {
		t.Fatalf("api_key not stripped: %+v", done.Payload)
	}
	got, _ := m.GetCommand(c1.ID)
	if got.Payload.APIKey != "" || got.Status != apitypes.CommandStatusSucceeded {
		t.Fatalf("get after complete: %+v", got)
	}

	pulled3, err := m.PullCommands("m1", 1)
	if err != nil || len(pulled3) != 1 || pulled3[0].ID != c2.ID {
		t.Fatalf("pull second: %+v err=%v", pulled3, err)
	}
}

func TestMemoryCommandTimeout(t *testing.T) {
	m := NewMemory(10)
	cmd, err := m.EnqueueCommand("m1", apitypes.EnqueueCommandRequest{
		App:     "claude",
		Type:    apitypes.CommandTypeUpdateProvider,
		Payload: apitypes.CommandPayload{ProviderID: "x", APIKey: "k"},
	})
	if err != nil {
		t.Fatal(err)
	}
	// backdate created_at
	m.mu.Lock()
	c := m.commands[cmd.ID]
	c.CreatedAt = time.Now().UTC().Add(-time.Duration(CommandQueuedTimeoutSec+5) * time.Second)
	m.commands[cmd.ID] = c
	m.mu.Unlock()

	n := m.ExpireCommands(time.Now().UTC())
	if n != 1 {
		t.Fatalf("expire n=%d", n)
	}
	got, err := m.GetCommand(cmd.ID)
	if err != nil || got.Status != apitypes.CommandStatusTimedOut || got.Payload.APIKey != "" {
		t.Fatalf("got=%+v err=%v", got, err)
	}
}

func TestSQLiteProvidersAndCommands(t *testing.T) {
	dir := t.TempDir()
	s, err := NewSQLite(filepath.Join(dir, "t.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()

	if err := s.ApplyProvidersReport(apitypes.ProvidersReportRequest{
		MachineID: "m1",
		Apps: []apitypes.ProviderAppSnapshot{{
			App: "codex", CurrentID: "a",
			Providers: []apitypes.ProviderInfo{{ID: "a", Name: "A"}},
		}},
	}); err != nil {
		t.Fatal(err)
	}
	list, err := s.ListProviders("m1", "all")
	if err != nil || len(list.Apps) != 1 {
		t.Fatalf("list=%+v err=%v", list, err)
	}

	cmd, err := s.EnqueueCommand("m1", apitypes.EnqueueCommandRequest{
		App:     "codex",
		Type:    apitypes.CommandTypeSwitchProvider,
		Payload: apitypes.CommandPayload{ProviderID: "a", APIKey: "secret"},
	})
	if err != nil {
		t.Fatal(err)
	}
	pulled, err := s.PullCommands("m1", 1)
	if err != nil || len(pulled) != 1 {
		t.Fatalf("pull=%+v err=%v", pulled, err)
	}
	// lease holds second pull
	empty, _ := s.PullCommands("m1", 1)
	if len(empty) != 0 {
		t.Fatalf("expected empty: %+v", empty)
	}
	done, err := s.CompleteCommand(cmd.ID, apitypes.CommandResultRequest{
		MachineID: "m1",
		Status:    apitypes.CommandStatusFailed,
		ErrorMessage: "no such provider",
		ProvidersReport: &apitypes.ProvidersReportRequest{
			MachineID: "m1",
			Apps: []apitypes.ProviderAppSnapshot{{
				App: "codex", CurrentID: "a",
				Providers: []apitypes.ProviderInfo{{ID: "a", Name: "A2"}},
			}},
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	if done.Payload.APIKey != "" || done.Status != apitypes.CommandStatusFailed {
		t.Fatalf("done=%+v", done)
	}
	list, _ = s.ListProviders("m1", "codex")
	if list.Apps[0].Providers[0].Name != "A2" {
		t.Fatalf("snapshot not applied: %+v", list)
	}
}
