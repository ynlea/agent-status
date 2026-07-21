package ccswitch

import (
	"encoding/hex"
	"crypto/rand"
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
	return &Adapter{DBPath: dbPath, Bin: resolveBin(bin)}
}

// resolveBin finds cc-switch on PATH or common user install locations.
// Service environments (systemd / Windows services) often lack the user PATH.
func resolveBin(bin string) string {
	bin = strings.TrimSpace(bin)
	if bin == "" {
		bin = "cc-switch"
	}
	if filepath.IsAbs(bin) {
		return bin
	}
	// relative path that exists as-is
	if strings.Contains(bin, string(os.PathSeparator)) || strings.Contains(bin, "/") || strings.Contains(bin, `\`) {
		if st, err := os.Stat(bin); err == nil && !st.IsDir() {
			return bin
		}
	}
	if path, err := exec.LookPath(bin); err == nil {
		return path
	}
	// only probe fallbacks for the default command name
	base := filepath.Base(bin)
	if base != "cc-switch" && base != "cc-switch.exe" {
		return bin
	}
	home, _ := os.UserHomeDir()
	candidates := []string{
		// Linux / macOS user installs
		filepath.Join(home, ".local", "bin", "cc-switch"),
		filepath.Join(home, ".local", "bin", "cc-switch.exe"),
		filepath.Join(home, "bin", "cc-switch"),
		filepath.Join(home, "bin", "cc-switch.exe"),
		// Windows official CLI install (per-user)
		filepath.Join(home, "AppData", "Local", "Programs", "cc-switch-cli", "cc-switch.exe"),
	}
	if localApp := strings.TrimSpace(os.Getenv("LOCALAPPDATA")); localApp != "" {
		candidates = append(candidates,
			filepath.Join(localApp, "Programs", "cc-switch-cli", "cc-switch.exe"),
		)
	}
	for _, c := range candidates {
		if st, err := os.Stat(c); err == nil && !st.IsDir() {
			return c
		}
	}
	return bin
}

// Available reports whether the sqlite file exists.
func (a *Adapter) Available() bool {
	if a == nil {
		return false
	}
	st, err := os.Stat(a.DBPath)
	return err == nil && !st.IsDir()
}

// CLIReady reports whether the cc-switch binary can be executed.
func (a *Adapter) CLIReady() bool {
	if a == nil {
		return false
	}
	bin := resolveBin(a.Bin)
	a.Bin = bin
	if filepath.IsAbs(bin) || strings.Contains(bin, string(os.PathSeparator)) {
		st, err := os.Stat(bin)
		return err == nil && !st.IsDir()
	}
	_, err := exec.LookPath(bin)
	return err == nil
}

// ResolvedBin returns the resolved executable path (best effort).
func (a *Adapter) ResolvedBin() string {
	if a == nil {
		return ""
	}
	bin := resolveBin(a.Bin)
	a.Bin = bin
	return bin
}

func (a *Adapter) openDB() (*sql.DB, error) {
	if !a.Available() {
		return nil, fmt.Errorf("cc-switch db not found: %s", a.DBPath)
	}
	// Short-lived connections; busy_timeout helps when cc-switch GUI holds the WAL.
	dsn := "file:" + a.DBPath + "?_pragma=busy_timeout(5000)&_pragma=journal_mode(WAL)"
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	// Ensure we can talk to the DB (surface lock errors early).
	if err := db.Ping(); err != nil {
		_ = db.Close()
		return nil, err
	}
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
	bin := resolveBin(a.Bin)
	a.Bin = bin
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, bin, "use", providerID, "-a", app)
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


func newProviderID() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		return fmt.Sprintf("prov-%d", time.Now().UnixNano())
	}
	// UUID-like with hyphens for readability
	h := hex.EncodeToString(b[:])
	return h[0:8] + "-" + h[8:12] + "-" + h[12:16] + "-" + h[16:20] + "-" + h[20:]
}

// CreateProvider inserts a custom provider from structured fields.
func (a *Adapter) CreateProvider(app string, p apitypes.CommandPayload) error {
	a.mu.Lock()
	defer a.mu.Unlock()
	if !apitypes.ValidProviderApp(app) {
		return fmt.Errorf("unsupported app %s", app)
	}
	name := strings.TrimSpace(p.Name)
	if name == "" {
		return fmt.Errorf("name required")
	}
	db, err := a.openDB()
	if err != nil {
		return err
	}
	defer db.Close()

	settings, err := buildNewSettings(app, p)
	if err != nil {
		return err
	}
	id := newProviderID()
	now := time.Now().UnixMilli()
	meta := `{"commonConfigEnabled":false,"endpointAutoSelect":true}`
	_, err = db.Exec(`
INSERT INTO providers(
  id, app_type, name, settings_config, website_url, category, created_at,
  meta, is_current, in_failover_queue, cost_multiplier
) VALUES(?,?,?,?,?,?,?,?,0,0,'1.0')`,
		id, app, name, settings, strings.TrimSpace(p.BaseURL), "custom", now, meta,
	)
	return err
}


func buildNewSettings(app string, p apitypes.CommandPayload) (string, error) {
	switch app {
	case apitypes.ProviderAppCodex:
		model := strings.TrimSpace(p.Model)
		if model == "" {
			model = "gpt-5.4"
		}
		base := strings.TrimSpace(p.BaseURL)
		cfg := "model_provider = \"OpenAI\"\nmodel = \"" + escapeTOML(model) + "\"\n"
		if base != "" {
			cfg += "\n[model_providers.OpenAI]\nname = \"OpenAI\"\nbase_url = \"" + escapeTOML(base) + "\"\nwire_api = \"responses\"\n"
		}
		root := map[string]interface{}{
			"auth":   map[string]interface{}{},
			"config": cfg,
		}
		if strings.TrimSpace(p.APIKey) != "" {
			root["auth"] = map[string]interface{}{"OPENAI_API_KEY": p.APIKey}
		}
		b, err := json.Marshal(root)
		return string(b), err
	case apitypes.ProviderAppClaude:
		env := map[string]interface{}{}
		if strings.TrimSpace(p.APIKey) != "" {
			env["ANTHROPIC_AUTH_TOKEN"] = p.APIKey
		}
		if strings.TrimSpace(p.BaseURL) != "" {
			env["ANTHROPIC_BASE_URL"] = p.BaseURL
		}
		if strings.TrimSpace(p.AnthropicModel) != "" {
			env["ANTHROPIC_MODEL"] = p.AnthropicModel
		}
		if strings.TrimSpace(p.DefaultHaikuModel) != "" {
			env["ANTHROPIC_DEFAULT_HAIKU_MODEL"] = p.DefaultHaikuModel
		}
		if strings.TrimSpace(p.DefaultSonnetModel) != "" {
			env["ANTHROPIC_DEFAULT_SONNET_MODEL"] = p.DefaultSonnetModel
		}
		if strings.TrimSpace(p.DefaultOpusModel) != "" {
			env["ANTHROPIC_DEFAULT_OPUS_MODEL"] = p.DefaultOpusModel
		}
		root := map[string]interface{}{"env": env}
		if strings.TrimSpace(p.ModelAlias) != "" {
			root["model"] = p.ModelAlias
		}
		b, err := json.Marshal(root)
		return string(b), err
	default:
		return "", fmt.Errorf("unsupported app")
	}
}

func escapeTOML(s string) string {
	s = strings.ReplaceAll(s, `\`, `\\`)
	s = strings.ReplaceAll(s, `"`, `\"`)
	return s
}

// DeleteProvider removes a non-current provider.
func (a *Adapter) DeleteProvider(app, providerID string) error {
	a.mu.Lock()
	defer a.mu.Unlock()
	if !apitypes.ValidProviderApp(app) {
		return fmt.Errorf("unsupported app %s", app)
	}
	if strings.TrimSpace(providerID) == "" {
		return fmt.Errorf("provider_id required")
	}
	db, err := a.openDB()
	if err != nil {
		return err
	}
	defer db.Close()

	var isCur bool
	var category string
	err = db.QueryRow(`SELECT is_current, COALESCE(category,'') FROM providers WHERE id=? AND app_type=?`,
		providerID, app).Scan(&isCur, &category)
	if err == sql.ErrNoRows {
		return fmt.Errorf("provider not found")
	}
	if err != nil {
		return err
	}
	if isCur {
		return fmt.Errorf("cannot delete current provider; switch away first")
	}
	if category == "official" || providerID == "codex-official" {
		return fmt.Errorf("cannot delete official provider")
	}
	if _, err := db.Exec(`DELETE FROM provider_endpoints WHERE provider_id=? AND app_type=?`, providerID, app); err != nil {
		// table may not exist on older DBs
		_ = err
	}
	res, err := db.Exec(`DELETE FROM providers WHERE id=? AND app_type=?`, providerID, app)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return fmt.Errorf("provider not found")
	}
	return nil
}

// DuplicateProvider clones a provider row with a new id and name suffix.
func (a *Adapter) DuplicateProvider(app, providerID string) error {
	a.mu.Lock()
	defer a.mu.Unlock()
	if !apitypes.ValidProviderApp(app) {
		return fmt.Errorf("unsupported app %s", app)
	}
	if strings.TrimSpace(providerID) == "" {
		return fmt.Errorf("provider_id required")
	}
	db, err := a.openDB()
	if err != nil {
		return err
	}
	defer db.Close()

	var (
		name, settings, website, category, notes, icon, iconColor, meta sql.NullString
		createdAt                                                       sql.NullInt64
		sortIndex                                                       sql.NullInt64
		costMult                                                        sql.NullString
	)
	err = db.QueryRow(`
SELECT name, settings_config, website_url, category, created_at, sort_index, notes, icon, icon_color, meta, cost_multiplier
FROM providers WHERE id=? AND app_type=?`, providerID, app).Scan(
		&name, &settings, &website, &category, &createdAt, &sortIndex, &notes, &icon, &iconColor, &meta, &costMult,
	)
	if err == sql.ErrNoRows {
		return fmt.Errorf("provider not found")
	}
	if err != nil {
		return err
	}
	newID := newProviderID()
	newName := strings.TrimSpace(name.String)
	if newName == "" {
		newName = "copy"
	} else {
		newName = newName + " copy"
	}
	now := time.Now().UnixMilli()
	_, err = db.Exec(`
INSERT INTO providers(
  id, app_type, name, settings_config, website_url, category, created_at,
  sort_index, notes, icon, icon_color, meta, is_current, in_failover_queue, cost_multiplier
) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,0,0,?)`,
		newID, app, newName, settings.String, website.String, nullStr(category, "custom"), now,
		sortIndex.Int64, notes.String, icon.String, iconColor.String, nullStr(meta, "{}"),
		nullStr(costMult, "1.0"),
	)
	return err
}

func nullStr(ns sql.NullString, def string) string {
	if ns.Valid && ns.String != "" {
		return ns.String
	}
	return def
}

// Execute runs a leased machine command.
func (a *Adapter) Execute(cmd apitypes.MachineCommand) error {
	switch cmd.Type {
	case apitypes.CommandTypeSwitchProvider:
		return a.SwitchProvider(cmd.App, cmd.Payload.ProviderID)
	case apitypes.CommandTypeUpdateProvider:
		return a.UpdateProvider(cmd.App, cmd.Payload)
	case apitypes.CommandTypeRefreshProviders:
		if !a.Available() {
			return fmt.Errorf("cc-switch database not found")
		}
		return nil
	case apitypes.CommandTypeCreateProvider:
		return a.CreateProvider(cmd.App, cmd.Payload)
	case apitypes.CommandTypeDeleteProvider:
		return a.DeleteProvider(cmd.App, cmd.Payload.ProviderID)
	case apitypes.CommandTypeDuplicateProvider:
		return a.DuplicateProvider(cmd.App, cmd.Payload.ProviderID)
	default:
		return fmt.Errorf("unknown command type %s", cmd.Type)
	}
}
