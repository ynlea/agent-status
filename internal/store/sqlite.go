package store

import (
	"database/sql"
	"fmt"
	"strings"
	"time"

	_ "modernc.org/sqlite"

	"github.com/ynlea/agent-status/pkg/apitypes"
)

// SQLiteStore persists machines, sessions, and short history.
type SQLiteStore struct {
	db     *sql.DB
	prices *priceCache
}

func NewSQLite(path string) (*SQLiteStore, error) {
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	s := &SQLiteStore{db: db, prices: newPriceCache()}
	if err := s.migrate(); err != nil {
		_ = db.Close()
		return nil, err
	}
	if err := s.reloadPriceCache(); err != nil {
		_ = db.Close()
		return nil, err
	}
	return s, nil
}

func (s *SQLiteStore) Close() error { return s.db.Close() }

func (s *SQLiteStore) migrate() error {
	_, err := s.db.Exec(`
CREATE TABLE IF NOT EXISTS machines (
  machine_id   TEXT PRIMARY KEY,
  machine_name TEXT NOT NULL,
  platform     TEXT NOT NULL,
  online       INTEGER NOT NULL,
  last_seen_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS sessions (
  machine_id   TEXT NOT NULL,
  agent        TEXT NOT NULL,
  session_id   TEXT NOT NULL,
  machine_name TEXT,
  display_name TEXT,
  state        TEXT NOT NULL,
  message      TEXT,
  updated_at   TEXT NOT NULL,
  PRIMARY KEY (machine_id, agent, session_id)
);
CREATE TABLE IF NOT EXISTS history (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  machine_id   TEXT NOT NULL,
  machine_name TEXT,
  agent        TEXT NOT NULL,
  session_id   TEXT NOT NULL,
  display_name TEXT,
  from_state   TEXT,
  to_state     TEXT NOT NULL,
  message      TEXT,
  at           TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_history_at ON history(at);
CREATE TABLE IF NOT EXISTS usage_events (
  dedupe_key          TEXT PRIMARY KEY,
  machine_id          TEXT NOT NULL,
  agent               TEXT NOT NULL,
  model               TEXT NOT NULL,
  session_id          TEXT,
  occurred_at         TEXT NOT NULL,
  input_tokens        INTEGER NOT NULL DEFAULT 0,
  output_tokens       INTEGER NOT NULL DEFAULT 0,
  reasoning_tokens    INTEGER NOT NULL DEFAULT 0,
  cache_write_tokens  INTEGER NOT NULL DEFAULT 0,
  cache_hit_tokens    INTEGER NOT NULL DEFAULT 0,
  created_at          TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_usage_machine_at ON usage_events(machine_id, occurred_at);
CREATE INDEX IF NOT EXISTS idx_usage_agent_at ON usage_events(agent, occurred_at);
CREATE INDEX IF NOT EXISTS idx_usage_model_at ON usage_events(model, occurred_at);
CREATE TABLE IF NOT EXISTS model_prices (
  model_id             TEXT PRIMARY KEY,
  input_per_mtok       REAL NOT NULL,
  output_per_mtok      REAL NOT NULL,
  cache_read_per_mtok  REAL NOT NULL,
  cache_write_per_mtok REAL NOT NULL,
  currency             TEXT NOT NULL DEFAULT 'USD',
  source               TEXT NOT NULL DEFAULT 'bundled',
  updated_at           TEXT NOT NULL
);
`)
	if err != nil {
		return err
	}
	// Best-effort upgrades for existing databases.
	_, _ = s.db.Exec(`ALTER TABLE machines ADD COLUMN version TEXT NOT NULL DEFAULT ''`)
	return s.seedModelPrices()
}

func (s *SQLiteStore) seedModelPrices() error {
	now := time.Now().UTC().Format(time.RFC3339Nano)
	for _, p := range bundledPublicPrices {
		id := NormalizeModelID(p.ModelID)
		if id == "" {
			continue
		}
		_, err := s.db.Exec(`
INSERT INTO model_prices(model_id, input_per_mtok, output_per_mtok, cache_read_per_mtok, cache_write_per_mtok, currency, source, updated_at)
VALUES(?,?,?,?,?,'USD',?,?)
ON CONFLICT(model_id) DO NOTHING
`, id, p.InputPerM, p.OutputPerM, p.CacheReadPerM, p.CacheWritePerM, SourceBundled, now)
		if err != nil {
			return err
		}
	}
	for _, p := range overridePublicPrices {
		id := NormalizeModelID(p.ModelID)
		if id == "" {
			continue
		}
		_, err := s.db.Exec(`
INSERT INTO model_prices(model_id, input_per_mtok, output_per_mtok, cache_read_per_mtok, cache_write_per_mtok, currency, source, updated_at)
VALUES(?,?,?,?,?,'USD',?,?)
ON CONFLICT(model_id) DO UPDATE SET
  input_per_mtok=excluded.input_per_mtok,
  output_per_mtok=excluded.output_per_mtok,
  cache_read_per_mtok=excluded.cache_read_per_mtok,
  cache_write_per_mtok=excluded.cache_write_per_mtok,
  source=excluded.source,
  updated_at=excluded.updated_at
`, id, p.InputPerM, p.OutputPerM, p.CacheReadPerM, p.CacheWritePerM, SourceOverride, now)
		if err != nil {
			return err
		}
	}
	return nil
}

func (s *SQLiteStore) reloadPriceCache() error {
	rows, err := s.db.Query(`
SELECT model_id, input_per_mtok, output_per_mtok, cache_read_per_mtok, cache_write_per_mtok, source
FROM model_prices`)
	if err != nil {
		return err
	}
	defer rows.Close()
	var list []ModelPrice
	for rows.Next() {
		var p ModelPrice
		if err := rows.Scan(&p.ModelID, &p.InputPerM, &p.OutputPerM, &p.CacheReadPerM, &p.CacheWritePerM, &p.Source); err != nil {
			return err
		}
		list = append(list, p)
	}
	if err := rows.Err(); err != nil {
		return err
	}
	s.prices.loadAll(list)
	return nil
}

func (s *SQLiteStore) LookupModelPrice(model string) (ModelPrice, bool) {
	return s.prices.lookup(model)
}

func (s *SQLiteStore) ListModelPrices() []ModelPrice {
	return s.prices.snapshot()
}

func (s *SQLiteStore) UpsertModelPrice(p ModelPrice, source string) error {
	id := NormalizeModelID(p.ModelID)
	if id == "" {
		return fmt.Errorf("empty model id")
	}
	if source == "" {
		source = SourceBundled
	}
	// Check existing source for override protection.
	var existingSource string
	err := s.db.QueryRow(`SELECT source FROM model_prices WHERE model_id=?`, id).Scan(&existingSource)
	if err == nil && !canReplace(existingSource, source) {
		return nil
	}
	if err != nil && err != sql.ErrNoRows {
		return err
	}

	// Merge cache fields when openrouter omits them.
	if source == SourceOpenRouter {
		if old, ok := s.prices.lookup(id); ok {
			if p.CacheReadPerM == 0 && old.CacheReadPerM != 0 {
				p.CacheReadPerM = old.CacheReadPerM
			}
			if p.CacheWritePerM == 0 && old.CacheWritePerM != 0 {
				p.CacheWritePerM = old.CacheWritePerM
			}
		}
	}

	now := time.Now().UTC().Format(time.RFC3339Nano)
	_, err = s.db.Exec(`
INSERT INTO model_prices(model_id, input_per_mtok, output_per_mtok, cache_read_per_mtok, cache_write_per_mtok, currency, source, updated_at)
VALUES(?,?,?,?,?,'USD',?,?)
ON CONFLICT(model_id) DO UPDATE SET
  input_per_mtok=excluded.input_per_mtok,
  output_per_mtok=excluded.output_per_mtok,
  cache_read_per_mtok=excluded.cache_read_per_mtok,
  cache_write_per_mtok=excluded.cache_write_per_mtok,
  source=excluded.source,
  updated_at=excluded.updated_at
WHERE model_prices.source != 'override' OR excluded.source = 'override'
`, id, p.InputPerM, p.OutputPerM, p.CacheReadPerM, p.CacheWritePerM, source, now)
	if err != nil {
		return err
	}
	p.ModelID = id
	p.Source = source
	s.prices.upsert(p, source)
	return nil
}

func (s *SQLiteStore) ApplyUsageReport(req apitypes.UsageReportRequest) (accepted, duplicates int) {
	if req.MachineID == "" {
		return 0, 0
	}
	now := req.ReportedAt
	if now.IsZero() {
		now = time.Now().UTC()
	}
	tx, err := s.db.Begin()
	if err != nil {
		return 0, 0
	}
	defer func() { _ = tx.Rollback() }()

	_, _ = tx.Exec(`
INSERT INTO machines(machine_id, machine_name, platform, online, last_seen_at)
VALUES(?,?,?,?,?)
ON CONFLICT(machine_id) DO UPDATE SET
  machine_name=CASE WHEN excluded.machine_name != '' THEN excluded.machine_name ELSE machines.machine_name END,
  platform=CASE WHEN excluded.platform != '' THEN excluded.platform ELSE machines.platform END,
  online=1,
  last_seen_at=excluded.last_seen_at
`, req.MachineID, req.MachineName, req.Platform, 1, now.Format(time.RFC3339Nano))

	for _, raw := range req.Events {
		e, ok := sanitizeUsageEvent(req.MachineID, raw)
		if !ok {
			continue
		}
		res, err := tx.Exec(`
INSERT INTO usage_events(
  dedupe_key, machine_id, agent, model, session_id, occurred_at,
  input_tokens, output_tokens, reasoning_tokens, cache_write_tokens, cache_hit_tokens, created_at
) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)
ON CONFLICT(dedupe_key) DO NOTHING
`, e.DedupeKey, e.MachineID, e.Agent, e.Model, e.SessionID, e.OccurredAt.UTC().Format(time.RFC3339Nano),
			e.InputTokens, e.OutputTokens, e.ReasoningTokens, e.CacheWriteTokens, e.CacheHitTokens,
			now.Format(time.RFC3339Nano))
		if err != nil {
			continue
		}
		n, _ := res.RowsAffected()
		if n == 0 {
			duplicates++
		} else {
			accepted++
		}
	}
	if err := tx.Commit(); err != nil {
		return 0, 0
	}
	return accepted, duplicates
}

func (s *SQLiteStore) usageWhere(q apitypes.UsageQuery) (string, []interface{}) {
	var (
		args  []interface{}
		where []string
	)
	if !q.From.IsZero() {
		where = append(where, "occurred_at >= ?")
		args = append(args, q.From.UTC().Format(time.RFC3339Nano))
	}
	if !q.To.IsZero() {
		where = append(where, "occurred_at <= ?")
		args = append(args, q.To.UTC().Format(time.RFC3339Nano))
	}
	if q.MachineID != "" {
		where = append(where, "machine_id = ?")
		args = append(args, q.MachineID)
	}
	if q.Agent != "" {
		where = append(where, "agent = ?")
		args = append(args, strings.ToLower(q.Agent))
	}
	if q.Model != "" {
		where = append(where, "model = ?")
		args = append(args, q.Model)
	}
	clause := ""
	if len(where) > 0 {
		clause = " WHERE " + strings.Join(where, " AND ")
	}
	return clause, args
}

// aggregateByModel runs SUM(*) GROUP BY model for pricing-accurate rollups.
func (s *SQLiteStore) aggregateByModel(q apitypes.UsageQuery) map[string]apitypes.UsageMetrics {
	clause, args := s.usageWhere(q)
	sqlStr := `SELECT model,
 COALESCE(SUM(input_tokens),0), COALESCE(SUM(output_tokens),0), COALESCE(SUM(reasoning_tokens),0),
 COALESCE(SUM(cache_write_tokens),0), COALESCE(SUM(cache_hit_tokens),0), COALESCE(COUNT(*),0)
 FROM usage_events` + clause + ` GROUP BY model`
	rows, err := s.db.Query(sqlStr, args...)
	if err != nil {
		return map[string]apitypes.UsageMetrics{}
	}
	defer rows.Close()
	out := map[string]apitypes.UsageMetrics{}
	for rows.Next() {
		var model string
		var in, outn, reason, cw, ch, n int64
		if err := rows.Scan(&model, &in, &outn, &reason, &cw, &ch, &n); err != nil {
			continue
		}
		if model == "" {
			model = "unknown"
		}
		m := metricsFromParts(in, outn, reason, cw, ch, n)
		out[model] = m
	}
	return out
}

func (s *SQLiteStore) UsageSummary(q apitypes.UsageQuery) apitypes.UsageSummaryResponse {
	return finalizeSummaryFromModelMap(s.LookupModelPrice, q, s.aggregateByModel(q))
}

func (s *SQLiteStore) UsageBreakdown(q apitypes.UsageQuery) apitypes.UsageBreakdownResponse {
	groupBy := validateGroupBy(q.GroupBy)
	clause, args := s.usageWhere(q)

	var groupExpr string
	switch groupBy {
	case "agent":
		groupExpr = "agent"
	case "machine":
		groupExpr = "machine_id"
	case "day":
		// occurred_at is RFC3339; first 10 chars are YYYY-MM-DD in UTC storage
		groupExpr = "substr(occurred_at, 1, 10)"
	case "hour":
		// YYYY-MM-DDTHH
		groupExpr = "substr(occurred_at, 1, 13)"
	default:
		groupExpr = "model"
	}

	sqlStr := `SELECT ` + groupExpr + ` AS gkey, model,
 COALESCE(SUM(input_tokens),0), COALESCE(SUM(output_tokens),0), COALESCE(SUM(reasoning_tokens),0),
 COALESCE(SUM(cache_write_tokens),0), COALESCE(SUM(cache_hit_tokens),0), COALESCE(COUNT(*),0)
 FROM usage_events` + clause + ` GROUP BY gkey, model`

	rows, err := s.db.Query(sqlStr, args...)
	if err != nil {
		return finalizeBreakdown(s.LookupModelPrice, q, groupBy, map[string]map[string]apitypes.UsageMetrics{})
	}
	defer rows.Close()
	groups := map[string]map[string]apitypes.UsageMetrics{}
	for rows.Next() {
		var gkey, model string
		var in, outn, reason, cw, ch, n int64
		if err := rows.Scan(&gkey, &model, &in, &outn, &reason, &cw, &ch, &n); err != nil {
			continue
		}
		if gkey == "" {
			gkey = "unknown"
		}
		if model == "" {
			model = "unknown"
		}
		if groups[gkey] == nil {
			groups[gkey] = map[string]apitypes.UsageMetrics{}
		}
		m := groups[gkey][model]
		m.InputTokens += in
		m.OutputTokens += outn
		m.ReasoningTokens += reason
		m.CacheWriteTokens += cw
		m.CacheHitTokens += ch
		m.EventCount += n
		groups[gkey][model] = m
	}
	return finalizeBreakdown(s.LookupModelPrice, q, groupBy, groups)
}

func (s *SQLiteStore) ApplyReport(req apitypes.ReportRequest) (changed []apitypes.Session, wasOnline bool) {
	now := req.ReportedAt
	if now.IsZero() {
		now = time.Now().UTC()
	}

	tx, err := s.db.Begin()
	if err != nil {
		return nil, false
	}
	defer func() { _ = tx.Rollback() }()

	var online int
	var prevName string
	err = tx.QueryRow(`SELECT online, machine_name FROM machines WHERE machine_id = ?`, req.MachineID).Scan(&online, &prevName)
	if err == nil {
		wasOnline = online == 1
	} else if err != sql.ErrNoRows {
		return nil, false
	}

	_, err = tx.Exec(`
INSERT INTO machines(machine_id, machine_name, platform, version, online, last_seen_at)
VALUES(?,?,?,?,?,?)
ON CONFLICT(machine_id) DO UPDATE SET
  machine_name=excluded.machine_name,
  platform=excluded.platform,
  version=CASE WHEN excluded.version != '' THEN excluded.version ELSE machines.version END,
  online=1,
  last_seen_at=excluded.last_seen_at
`, req.MachineID, req.MachineName, req.Platform, req.Version, 1, now.Format(time.RFC3339Nano))
	if err != nil {
		return nil, false
	}

	// Report is a full snapshot for this machine: upsert present sessions, drop the rest.
	keep := make(map[string]struct{}, len(req.Sessions))
	for _, sess := range req.Sessions {
		if sess.SessionID == "" || sess.Agent == "" || !sess.State.Valid() {
			continue
		}
		keep[sess.Agent+"\x00"+sess.SessionID] = struct{}{}
		sess.MachineID = req.MachineID
		if sess.MachineName == "" {
			sess.MachineName = req.MachineName
		}
		if sess.UpdatedAt.IsZero() {
			sess.UpdatedAt = now
		}

		var oldState string
		err = tx.QueryRow(`
SELECT state FROM sessions WHERE machine_id=? AND agent=? AND session_id=?
`, req.MachineID, sess.Agent, sess.SessionID).Scan(&oldState)
		exists := err == nil
		if err != nil && err != sql.ErrNoRows {
			return nil, false
		}
		if !exists || oldState != string(sess.State) {
			from := apitypes.SessionState("")
			if exists {
				from = apitypes.SessionState(oldState)
			}
			_, err = tx.Exec(`
INSERT INTO history(machine_id, machine_name, agent, session_id, display_name, from_state, to_state, message, at)
VALUES(?,?,?,?,?,?,?,?,?)
`, sess.MachineID, sess.MachineName, sess.Agent, sess.SessionID, sess.DisplayName, string(from), string(sess.State), sess.Message, sess.UpdatedAt.Format(time.RFC3339Nano))
			if err != nil {
				return nil, false
			}
			changed = append(changed, sess)
		}
		_, err = tx.Exec(`
INSERT INTO sessions(machine_id, agent, session_id, machine_name, display_name, state, message, updated_at)
VALUES(?,?,?,?,?,?,?,?)
ON CONFLICT(machine_id, agent, session_id) DO UPDATE SET
  machine_name=excluded.machine_name,
  display_name=excluded.display_name,
  state=excluded.state,
  message=excluded.message,
  updated_at=excluded.updated_at
`, sess.MachineID, sess.Agent, sess.SessionID, sess.MachineName, sess.DisplayName, string(sess.State), sess.Message, sess.UpdatedAt.Format(time.RFC3339Nano))
		if err != nil {
			return nil, false
		}
	}

	// Remove sessions no longer reported by this machine (prevents forever-zombies).
	rows, err := tx.Query(`
SELECT agent, session_id, display_name, state, message FROM sessions WHERE machine_id=?
`, req.MachineID)
	if err != nil {
		return nil, false
	}
	type staleRow struct {
		agent, sid, display, state, message string
	}
	var stale []staleRow
	for rows.Next() {
		var r staleRow
		if err := rows.Scan(&r.agent, &r.sid, &r.display, &r.state, &r.message); err != nil {
			rows.Close()
			return nil, false
		}
		if _, ok := keep[r.agent+"\x00"+r.sid]; !ok {
			stale = append(stale, r)
		}
	}
	rows.Close()
	for _, r := range stale {
		if r.state != string(apitypes.StateIdle) {
			gone := apitypes.Session{
				MachineID:   req.MachineID,
				MachineName: req.MachineName,
				Agent:       r.agent,
				SessionID:   r.sid,
				DisplayName: r.display,
				State:       apitypes.StateIdle,
				Message:     r.message,
				UpdatedAt:   now,
			}
			_, err = tx.Exec(`
INSERT INTO history(machine_id, machine_name, agent, session_id, display_name, from_state, to_state, message, at)
VALUES(?,?,?,?,?,?,?,?,?)
`, req.MachineID, req.MachineName, r.agent, r.sid, r.display, r.state, string(apitypes.StateIdle), r.message, now.Format(time.RFC3339Nano))
			if err != nil {
				return nil, false
			}
			changed = append(changed, gone)
		}
		if _, err = tx.Exec(`
DELETE FROM sessions WHERE machine_id=? AND agent=? AND session_id=?
`, req.MachineID, r.agent, r.sid); err != nil {
			return nil, false
		}
	}

	if err := tx.Commit(); err != nil {
		return nil, false
	}
	return changed, wasOnline
}

func (s *SQLiteStore) ListMachines() []apitypes.Machine {
	rows, err := s.db.Query(`SELECT machine_id, machine_name, platform, COALESCE(version,''), online, last_seen_at FROM machines`)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var out []apitypes.Machine
	for rows.Next() {
		var m apitypes.Machine
		var online int
		var last string
		if err := rows.Scan(&m.MachineID, &m.MachineName, &m.Platform, &m.Version, &online, &last); err != nil {
			continue
		}
		m.Online = online == 1
		m.LastSeenAt, _ = time.Parse(time.RFC3339Nano, last)
		out = append(out, m)
	}
	if out == nil {
		out = []apitypes.Machine{}
	}
	return out
}

func (s *SQLiteStore) ListSessions(machineID string) []apitypes.Session {
	var rows *sql.Rows
	var err error
	if machineID == "" {
		rows, err = s.db.Query(`SELECT machine_id, agent, session_id, machine_name, display_name, state, message, updated_at FROM sessions`)
	} else {
		rows, err = s.db.Query(`SELECT machine_id, agent, session_id, machine_name, display_name, state, message, updated_at FROM sessions WHERE machine_id=?`, machineID)
	}
	if err != nil {
		return nil
	}
	defer rows.Close()
	var out []apitypes.Session
	for rows.Next() {
		var sess apitypes.Session
		var st, updated string
		if err := rows.Scan(&sess.MachineID, &sess.Agent, &sess.SessionID, &sess.MachineName, &sess.DisplayName, &st, &sess.Message, &updated); err != nil {
			continue
		}
		sess.State = apitypes.SessionState(st)
		sess.UpdatedAt, _ = time.Parse(time.RFC3339Nano, updated)
		out = append(out, sess)
	}
	if out == nil {
		out = []apitypes.Session{}
	}
	return out
}

func (s *SQLiteStore) ListHistory(limit int) []apitypes.HistoryEntry {
	if limit <= 0 {
		limit = 50
	}
	rows, err := s.db.Query(`
SELECT machine_id, machine_name, agent, session_id, display_name, from_state, to_state, message, at
FROM history ORDER BY id DESC LIMIT ?
`, limit)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var out []apitypes.HistoryEntry
	for rows.Next() {
		var e apitypes.HistoryEntry
		var from, to, at string
		if err := rows.Scan(&e.MachineID, &e.MachineName, &e.Agent, &e.SessionID, &e.DisplayName, &from, &to, &e.Message, &at); err != nil {
			continue
		}
		e.FromState = apitypes.SessionState(from)
		e.ToState = apitypes.SessionState(to)
		e.At, _ = time.Parse(time.RFC3339Nano, at)
		out = append(out, e)
	}
	if out == nil {
		out = []apitypes.HistoryEntry{}
	}
	return out
}

func (s *SQLiteStore) Cleanup(maxAgeSeconds int64, maxCount int, machineOfflineAfter int64) (historyDeleted int, machinesOffline int) {
	now := time.Now().UTC()
	if maxAgeSeconds > 0 {
		cut := now.Add(-time.Duration(maxAgeSeconds) * time.Second).Format(time.RFC3339Nano)
		res, err := s.db.Exec(`DELETE FROM history WHERE at < ?`, cut)
		if err == nil {
			n, _ := res.RowsAffected()
			historyDeleted += int(n)
		}
	}
	if maxCount > 0 {
		var total int
		_ = s.db.QueryRow(`SELECT COUNT(*) FROM history`).Scan(&total)
		if total > maxCount {
			extra := total - maxCount
			res, err := s.db.Exec(`DELETE FROM history WHERE id IN (SELECT id FROM history ORDER BY id ASC LIMIT ?)`, extra)
			if err == nil {
				n, _ := res.RowsAffected()
				historyDeleted += int(n)
			}
		}
	}
	if machineOfflineAfter > 0 {
		cut := now.Add(-time.Duration(machineOfflineAfter) * time.Second).Format(time.RFC3339Nano)
		res, err := s.db.Exec(`UPDATE machines SET online=0 WHERE online=1 AND last_seen_at < ?`, cut)
		if err == nil {
			n, _ := res.RowsAffected()
			machinesOffline = int(n)
		}
	}
	return historyDeleted, machinesOffline
}

// Ensure compile-time check.
var _ Store = (*SQLiteStore)(nil)
var _ Store = (*Memory)(nil)

// Path helper for tests.
func MustSQLite(path string) *SQLiteStore {
	s, err := NewSQLite(path)
	if err != nil {
		panic(fmt.Sprintf("sqlite: %v", err))
	}
	return s
}
