package ccswitch

import (
	"database/sql"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	_ "modernc.org/sqlite"

	"github.com/ynlea/agent-status/pkg/apitypes"
)

func TestTomlLineGetSet(t *testing.T) {
	cfg := `model = "gpt-5.4"
review_model = "gpt-5.5"

[model_providers.OpenAI]
name = "OpenAI"
base_url = "https://example.com/v1"
`
	if got := tomlGet(cfg, "model"); got != "gpt-5.4" {
		t.Fatalf("model=%q", got)
	}
	if got := tomlGet(cfg, "base_url"); got != "https://example.com/v1" {
		t.Fatalf("base_url=%q", got)
	}
	next := tomlSet(cfg, "model", "gpt-5.6")
	if tomlGet(next, "model") != "gpt-5.6" {
		t.Fatalf("set model failed: %s", next)
	}
	// preserve other lines
	if tomlGet(next, "base_url") != "https://example.com/v1" {
		t.Fatalf("base_url clobbered")
	}
	next = tomlSet(next, "base_url", "https://new.example/v1")
	if tomlGet(next, "base_url") != "https://new.example/v1" {
		t.Fatalf("set base_url failed")
	}
}

func TestListAndPatchClaudePreservesHooks(t *testing.T) {
	dir := t.TempDir()
	dbPath := filepath.Join(dir, "cc-switch.db")
	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		t.Fatal(err)
	}
	_, err = db.Exec(`
CREATE TABLE providers (
  id TEXT NOT NULL,
  app_type TEXT NOT NULL,
  name TEXT NOT NULL,
  settings_config TEXT NOT NULL,
  website_url TEXT,
  category TEXT,
  sort_index INTEGER,
  is_current INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (id, app_type)
);`)
	if err != nil {
		t.Fatal(err)
	}
	settings := map[string]interface{}{
		"model": "sonnet",
		"env": map[string]interface{}{
			"ANTHROPIC_AUTH_TOKEN":         "secret-token",
			"ANTHROPIC_BASE_URL":           "https://api.example",
			"ANTHROPIC_MODEL":              "m1",
			"ANTHROPIC_DEFAULT_HAIKU_MODEL": "h1",
			"ANTHROPIC_DEFAULT_SONNET_MODEL": "s1",
			"ANTHROPIC_DEFAULT_OPUS_MODEL": "o1",
		},
		"hooks": map[string]interface{}{
			"PreToolUse": []interface{}{
				map[string]interface{}{"matcher": "Bash"},
			},
		},
	}
	raw, _ := json.Marshal(settings)
	_, err = db.Exec(`INSERT INTO providers(id, app_type, name, settings_config, category, sort_index, is_current)
VALUES(?,?,?,?,?,?,?)`, "p1", "claude", "demo", string(raw), "custom", 0, 1)
	if err != nil {
		t.Fatal(err)
	}
	// codex row
	codexCfg := map[string]interface{}{
		"auth":   map[string]interface{}{"OPENAI_API_KEY": "sk-test"},
		"config": "model = \"gpt-5.4\"\nbase_url = \"https://codex.example/v1\"\n",
	}
	craw, _ := json.Marshal(codexCfg)
	_, err = db.Exec(`INSERT INTO providers(id, app_type, name, settings_config, category, sort_index, is_current)
VALUES(?,?,?,?,?,?,?)`, "c1", "codex", "cx", string(craw), "custom", 0, 1)
	if err != nil {
		t.Fatal(err)
	}
	db.Close()

	// fake bin that always succeeds
	bin := filepath.Join(dir, "fake-cc-switch")
	if err := os.WriteFile(bin, []byte("#!/bin/sh\nexit 0\n"), 0o755); err != nil {
		t.Fatal(err)
	}

	a := NewAdapter(dbPath, bin)
	apps, err := a.ListApps()
	if err != nil {
		t.Fatal(err)
	}
	if len(apps) != 2 {
		t.Fatalf("apps=%+v", apps)
	}
	var claude apitypes.ProviderAppSnapshot
	for _, app := range apps {
		if app.App == "claude" {
			claude = app
		}
	}
	if claude.CurrentID != "p1" || len(claude.Providers) != 1 {
		t.Fatalf("claude snap=%+v", claude)
	}
	p := claude.Providers[0]
	if !p.HasAPIKey || p.AnthropicModel != "m1" || p.ModelAlias != "sonnet" {
		t.Fatalf("mapped=%+v", p)
	}

	err = a.UpdateProvider("claude", apitypes.CommandPayload{
		ProviderID:     "p1",
		Name:           "demo2",
		AnthropicModel: "m2",
		// no api_key => leave secret
	})
	if err != nil {
		t.Fatal(err)
	}

	db2, _ := sql.Open("sqlite", dbPath)
	defer db2.Close()
	var name, settingsOut string
	if err := db2.QueryRow(`SELECT name, settings_config FROM providers WHERE id='p1'`).Scan(&name, &settingsOut); err != nil {
		t.Fatal(err)
	}
	if name != "demo2" {
		t.Fatalf("name=%s", name)
	}
	var root map[string]interface{}
	if err := json.Unmarshal([]byte(settingsOut), &root); err != nil {
		t.Fatal(err)
	}
	if _, ok := root["hooks"]; !ok {
		t.Fatalf("hooks wiped: %s", settingsOut)
	}
	env := root["env"].(map[string]interface{})
	if env["ANTHROPIC_MODEL"] != "m2" {
		t.Fatalf("model not patched: %v", env["ANTHROPIC_MODEL"])
	}
	if env["ANTHROPIC_AUTH_TOKEN"] != "secret-token" {
		t.Fatalf("token clobbered")
	}

	// codex model patch
	if err := a.UpdateProvider("codex", apitypes.CommandPayload{
		ProviderID: "c1",
		Model:      "gpt-5.6",
		BaseURL:    "https://new/v1",
	}); err != nil {
		t.Fatal(err)
	}
	var csettings string
	_ = db2.QueryRow(`SELECT settings_config FROM providers WHERE id='c1'`).Scan(&csettings)
	var croot map[string]interface{}
	_ = json.Unmarshal([]byte(csettings), &croot)
	cfg := croot["config"].(string)
	if tomlGet(cfg, "model") != "gpt-5.6" || tomlGet(cfg, "base_url") != "https://new/v1" {
		t.Fatalf("codex cfg=%s", cfg)
	}
}
