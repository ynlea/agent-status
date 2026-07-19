package store

import (
	"database/sql"
	"fmt"
	"time"

	_ "modernc.org/sqlite"

	"github.com/ynlea/agent-status/pkg/apitypes"
)

// SQLiteStore persists machines, sessions, and short history.
type SQLiteStore struct {
	db *sql.DB
}

func NewSQLite(path string) (*SQLiteStore, error) {
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	s := &SQLiteStore{db: db}
	if err := s.migrate(); err != nil {
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
`)
	return err
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
INSERT INTO machines(machine_id, machine_name, platform, online, last_seen_at)
VALUES(?,?,?,?,?)
ON CONFLICT(machine_id) DO UPDATE SET
  machine_name=excluded.machine_name,
  platform=excluded.platform,
  online=1,
  last_seen_at=excluded.last_seen_at
`, req.MachineID, req.MachineName, req.Platform, 1, now.Format(time.RFC3339Nano))
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
	rows, err := s.db.Query(`SELECT machine_id, machine_name, platform, online, last_seen_at FROM machines`)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var out []apitypes.Machine
	for rows.Next() {
		var m apitypes.Machine
		var online int
		var last string
		if err := rows.Scan(&m.MachineID, &m.MachineName, &m.Platform, &online, &last); err != nil {
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
