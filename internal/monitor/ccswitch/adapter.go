package ccswitch

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"

	_ "modernc.org/sqlite"

	"github.com/ynlea/agent-status/pkg/apitypes"
)

// Adapter reads/patches local cc-switch.db and runs CLI switch.
type Adapter struct {
	DBPath string
	Bin    string

	mu sync.Mutex
}

// DefaultDBPath returns ~/.cc-switch/cc-switch.db.
func DefaultDBPath() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".cc-switch", "cc-switch.db")
}

// NewAdapter builds an adapter with defaults for empty paths.
func NewAdapter(dbPath, bin string) *Adapter {
	if strings.TrimSpace(dbPath) == "" {
		dbPath = DefaultDBPath()
	}
	if strings.TrimSpace(bin) == "" {
		bin = "cc-switch"
	}
	return &Adapter{DBPath: dbPath, Bin: bin}
}

// Available reports whether the sqlite file exists.
func (a *Adapter) Available() bool {
	if a == nil {
		return false
	}
	st, err := os.Stat(a.DBPath)
	return err == nil && !st.IsDir()
}

func (a *Adapter) openDB() (*sql.DB, error) {
	if !a.Available() {
		return nil, fmt.Errorf("cc-switch db not found: %s", a.DBPath)
	}
	// read-write for patch; short-lived connections
	db, err := sql.Open("sqlite", a.DBPath)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	return db, nil
}

// ListApps returns redacted snapshots for codex and claude.
func (a *Adapter) ListApps() ([]apitypes.ProviderAppSnapshot, error) {
	a.mu.Lock()
	defer a.mu.Unlock()
	db, err := a.openDB()
	if err != nil {
		return nil, err
	}
	defer db.Close()

	out := make([]apitypes.ProviderAppSnapshot, 0, 2)
	for _, app := range []string{apitypes.ProviderAppCodex, apitypes.ProviderAppClaude} {
		snap, err := listApp(db, app)
		if err != nil {
			return nil, err
		}
		out = append(out, snap)
	}
	return out, nil
}

func listApp(db *sql.DB, app string) (apitypes.ProviderAppSnapshot, error) {
	rows, err := db.Query(`
SELECT id, name, website_url, category, is_current, settings_config
FROM providers WHERE app_type=? ORDER BY sort_index ASC, name ASC`, app)
	if err != nil {
		return apitypes.ProviderAppSnapshot{}, err
	}
	defer rows.Close()

	snap := apitypes.ProviderAppSnapshot{
		App:       app,
		Providers: []apitypes.ProviderInfo{},
	}
	for rows.Next() {
		var (
			id, name     string
			website, cat sql.NullString
			isCurrent    bool
			settings     string
		)
		if err := rows.Scan(&id, &name, &website, &cat, &isCurrent, &settings); err != nil {
			return snap, err
		}
		info := mapProvider(app, id, name, cat.String, settings)
		if isCurrent {
			snap.CurrentID = id
		}
		snap.Providers = append(snap.Providers, info)
	}
	return snap, rows.Err()
}

func mapProvider(app, id, name, category, settingsJSON string) apitypes.ProviderInfo {
	info := apitypes.ProviderInfo{
		ID:       id,
		Name:     name,
		Category: category,
	}
	var root map[string]interface{}
	if err := json.Unmarshal([]byte(settingsJSON), &root); err != nil {
		return info
	}
	switch app {
	case apitypes.ProviderAppCodex:
		if auth, ok := root["auth"].(map[string]interface{}); ok {
			if key, _ := auth["OPENAI_API_KEY"].(string); strings.TrimSpace(key) != "" {
				info.HasAPIKey = true
			}
		}
		cfg, _ := root["config"].(string)
		info.Model = tomlGet(cfg, "model")
		info.BaseURL = tomlGet(cfg, "base_url")
	case apitypes.ProviderAppClaude:
		if model, ok := root["model"].(string); ok {
			info.ModelAlias = model
		}
		env, _ := root["env"].(map[string]interface{})
		if env == nil {
			env = map[string]interface{}{}
		}
		if tok, _ := env["ANTHROPIC_AUTH_TOKEN"].(string); strings.TrimSpace(tok) != "" {
			info.HasAPIKey = true
		}
		if v, _ := env["ANTHROPIC_BASE_URL"].(string); v != "" {
			info.BaseURL = v
		}
		if v, _ := env["ANTHROPIC_MODEL"].(string); v != "" {
			info.AnthropicModel = v
		}
		if v, _ := env["ANTHROPIC_DEFAULT_HAIKU_MODEL"].(string); v != "" {
			info.DefaultHaikuModel = v
		}
		if v, _ := env["ANTHROPIC_DEFAULT_SONNET_MODEL"].(string); v != "" {
			info.DefaultSonnetModel = v
		}
		if v, _ := env["ANTHROPIC_DEFAULT_OPUS_MODEL"].(string); v != "" {
			info.DefaultOpusModel = v
		}
	}
	return info
}

// SwitchProvider runs: cc-switch use <id> -a <app>
func (a *Adapter) SwitchProvider(app, providerID string) error {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.switchUnlocked(app, providerID)
}

func (a *Adapter) switchUnlocked(app, providerID string) error {
	if !apitypes.ValidProviderApp(app) {
		return fmt.Errorf("unsupported app %s", app)
	}
	if strings.TrimSpace(providerID) == "" {
		return fmt.Errorf("provider_id required")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, a.Bin, "use", providerID, "-a", app)
	out, err := cmd.CombinedOutput()
	if err != nil {
		msg := strings.TrimSpace(string(out))
		if msg == "" {
			msg = err.Error()
		}
		// never include secrets; CLI output should be safe
		if len(msg) > 300 {
			msg = msg[:300]
		}
		return fmt.Errorf("cc-switch use failed: %s", msg)
	}
	return nil
}

// UpdateProvider patches settings_config fields present in payload, then
// re-applies live config if the provider is current.
func (a *Adapter) UpdateProvider(app string, payload apitypes.CommandPayload) error {
	a.mu.Lock()
	defer a.mu.Unlock()

	if !apitypes.ValidProviderApp(app) {
		return fmt.Errorf("unsupported app %s", app)
	}
	if strings.TrimSpace(payload.ProviderID) == "" {
		return fmt.Errorf("provider_id required")
	}

	db, err := a.openDB()
	if err != nil {
		return err
	}
	defer db.Close()

	var (
		name     string
		settings string
		isCur    bool
	)
	err = db.QueryRow(`
SELECT name, settings_config, is_current FROM providers
WHERE id=? AND app_type=?`, payload.ProviderID, app).Scan(&name, &settings, &isCur)
	if err == sql.ErrNoRows {
		return fmt.Errorf("provider not found: %s", payload.ProviderID)
	}
	if err != nil {
		return err
	}

	newName := name
	if strings.TrimSpace(payload.Name) != "" {
		newName = strings.TrimSpace(payload.Name)
	}

	newSettings, err := patchSettings(app, settings, payload)
	if err != nil {
		return err
	}

	_, err = db.Exec(`
UPDATE providers SET name=?, settings_config=?
WHERE id=? AND app_type=?`, newName, newSettings, payload.ProviderID, app)
	if err != nil {
		return err
	}

	if isCur {
		if err := a.switchUnlocked(app, payload.ProviderID); err != nil {
			return fmt.Errorf("db updated but apply live failed: %w", err)
		}
	}
	return nil
}

func patchSettings(app, settingsJSON string, p apitypes.CommandPayload) (string, error) {
	var root map[string]interface{}
	if err := json.Unmarshal([]byte(settingsJSON), &root); err != nil {
		return "", fmt.Errorf("invalid settings_config json: %w", err)
	}
	if root == nil {
		root = map[string]interface{}{}
	}

	switch app {
	case apitypes.ProviderAppCodex:
		if p.APIKey != "" {
			auth, _ := root["auth"].(map[string]interface{})
			if auth == nil {
				auth = map[string]interface{}{}
			}
			auth["OPENAI_API_KEY"] = p.APIKey
			root["auth"] = auth
		}
		cfg, _ := root["config"].(string)
		if p.Model != "" {
			cfg = tomlSet(cfg, "model", p.Model)
		}
		if p.BaseURL != "" {
			cfg = tomlSet(cfg, "base_url", p.BaseURL)
		}
		root["config"] = cfg
	case apitypes.ProviderAppClaude:
		if p.ModelAlias != "" {
			root["model"] = p.ModelAlias
		}
		env, _ := root["env"].(map[string]interface{})
		if env == nil {
			env = map[string]interface{}{}
		}
		// deep-merge only provided keys; preserve hooks and other env
		if p.APIKey != "" {
			env["ANTHROPIC_AUTH_TOKEN"] = p.APIKey
		}
		if p.BaseURL != "" {
			env["ANTHROPIC_BASE_URL"] = p.BaseURL
		}
		if p.AnthropicModel != "" {
			env["ANTHROPIC_MODEL"] = p.AnthropicModel
		}
		if p.DefaultHaikuModel != "" {
			env["ANTHROPIC_DEFAULT_HAIKU_MODEL"] = p.DefaultHaikuModel
		}
		if p.DefaultSonnetModel != "" {
			env["ANTHROPIC_DEFAULT_SONNET_MODEL"] = p.DefaultSonnetModel
		}
		if p.DefaultOpusModel != "" {
			env["ANTHROPIC_DEFAULT_OPUS_MODEL"] = p.DefaultOpusModel
		}
		root["env"] = env
	}

	raw, err := json.Marshal(root)
	if err != nil {
		return "", err
	}
	return string(raw), nil
}

// Execute runs a leased machine command.
func (a *Adapter) Execute(cmd apitypes.MachineCommand) error {
	switch cmd.Type {
	case apitypes.CommandTypeSwitchProvider:
		return a.SwitchProvider(cmd.App, cmd.Payload.ProviderID)
	case apitypes.CommandTypeUpdateProvider:
		return a.UpdateProvider(cmd.App, cmd.Payload)
	default:
		return fmt.Errorf("unknown command type %s", cmd.Type)
	}
}
