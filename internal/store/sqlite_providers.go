package store

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/ynlea/agent-status/pkg/apitypes"
)

func (s *SQLiteStore) ApplyProvidersReport(req apitypes.ProvidersReportRequest) error {
	if strings.TrimSpace(req.MachineID) == "" {
		return fmt.Errorf("machine_id required")
	}
	now := req.ReportedAt
	if now.IsZero() {
		now = time.Now().UTC()
	}
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	// Touch machine last_seen lightly if row exists; do not invent offline machines.
	_, _ = tx.Exec(`
UPDATE machines SET last_seen_at=?, online=1
WHERE machine_id=?`, now.Format(time.RFC3339Nano), req.MachineID)

	for _, appSnap := range req.Apps {
		if !apitypes.ValidProviderApp(appSnap.App) {
			continue
		}
		if appSnap.Providers == nil {
			appSnap.Providers = []apitypes.ProviderInfo{}
		}
		raw, err := json.Marshal(appSnap)
		if err != nil {
			return err
		}
		_, err = tx.Exec(`
INSERT INTO provider_snapshots(machine_id, app, payload_json, updated_at)
VALUES(?,?,?,?)
ON CONFLICT(machine_id, app) DO UPDATE SET
  payload_json=excluded.payload_json,
  updated_at=excluded.updated_at
`, req.MachineID, appSnap.App, string(raw), now.Format(time.RFC3339Nano))
		if err != nil {
			return err
		}
	}
	return tx.Commit()
}

func (s *SQLiteStore) ListProviders(machineID, app string) (apitypes.ProvidersListResponse, error) {
	out := apitypes.ProvidersListResponse{
		MachineID: machineID,
		Apps:      []apitypes.ProviderAppSnapshot{},
	}
	if machineID == "" {
		return out, fmt.Errorf("machine_id required")
	}
	app = strings.TrimSpace(app)
	var (
		rows *sql.Rows
		err  error
	)
	if app == "" || app == "all" {
		rows, err = s.db.Query(`
SELECT payload_json, updated_at FROM provider_snapshots
WHERE machine_id=? ORDER BY app`, machineID)
	} else {
		if !apitypes.ValidProviderApp(app) {
			return out, fmt.Errorf("app must be codex|claude|all")
		}
		rows, err = s.db.Query(`
SELECT payload_json, updated_at FROM provider_snapshots
WHERE machine_id=? AND app=?`, machineID, app)
	}
	if err != nil {
		return out, err
	}
	defer rows.Close()

	var latest time.Time
	for rows.Next() {
		var payload, updated string
		if err := rows.Scan(&payload, &updated); err != nil {
			return out, err
		}
		var snap apitypes.ProviderAppSnapshot
		if err := json.Unmarshal([]byte(payload), &snap); err != nil {
			continue
		}
		if snap.Providers == nil {
			snap.Providers = []apitypes.ProviderInfo{}
		}
		out.Apps = append(out.Apps, snap)
		if t, err := time.Parse(time.RFC3339Nano, updated); err == nil {
			if t.After(latest) {
				latest = t
			}
		}
	}
	if err := rows.Err(); err != nil {
		return out, err
	}
	out.UpdatedAt = latest
	return out, nil
}

func (s *SQLiteStore) EnqueueCommand(machineID string, req apitypes.EnqueueCommandRequest) (apitypes.MachineCommand, error) {
	if err := validateEnqueue(machineID, req); err != nil {
		return apitypes.MachineCommand{}, err
	}
	now := time.Now().UTC()
	cmd := apitypes.MachineCommand{
		ID:        newCommandID(),
		MachineID: machineID,
		App:       req.App,
		Type:      req.Type,
		Payload:   req.Payload,
		Status:    apitypes.CommandStatusQueued,
		CreatedAt: now,
	}
	raw, err := json.Marshal(cmd.Payload)
	if err != nil {
		return apitypes.MachineCommand{}, err
	}
	_, err = s.db.Exec(`
INSERT INTO machine_commands(
  id, machine_id, app, type, payload_json, status, error_message, created_at
) VALUES(?,?,?,?,?,?, '',?)`,
		cmd.ID, cmd.MachineID, cmd.App, cmd.Type, string(raw), cmd.Status, now.Format(time.RFC3339Nano))
	if err != nil {
		return apitypes.MachineCommand{}, err
	}
	return cmd, nil
}

func (s *SQLiteStore) PullCommands(machineID string, limit int) ([]apitypes.MachineCommand, error) {
	if strings.TrimSpace(machineID) == "" {
		return nil, fmt.Errorf("machine_id required")
	}
	// Serial queue: at most one leased/running command per machine.
	limit = 1
	now := time.Now().UTC()
	_ = s.ExpireCommands(now)

	tx, err := s.db.Begin()
	if err != nil {
		return nil, err
	}
	defer func() { _ = tx.Rollback() }()

	// Serial: refuse while a non-expired running command exists.
	var running int
	if err := tx.QueryRow(`
SELECT COUNT(1) FROM machine_commands
WHERE machine_id=? AND status=?`, machineID, apitypes.CommandStatusRunning).Scan(&running); err != nil {
		return nil, err
	}
	if running > 0 {
		if err := tx.Commit(); err != nil {
			return nil, err
		}
		return []apitypes.MachineCommand{}, nil
	}

	rows, err := tx.Query(`
SELECT id, machine_id, app, type, payload_json, status, error_message, created_at
FROM machine_commands
WHERE machine_id=? AND status=?
ORDER BY created_at ASC
LIMIT ?`, machineID, apitypes.CommandStatusQueued, limit)
	if err != nil {
		return nil, err
	}
	var pending []apitypes.MachineCommand
	for rows.Next() {
		cmd, err := scanCommandRow(rows)
		if err != nil {
			rows.Close()
			return nil, err
		}
		pending = append(pending, cmd)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}

	leaseUntil := now.Add(time.Duration(CommandLeaseSec) * time.Second)
	out := make([]apitypes.MachineCommand, 0, len(pending))
	for _, cmd := range pending {
		_, err := tx.Exec(`
UPDATE machine_commands
SET status=?, started_at=?, lease_until=?
WHERE id=? AND status=?`,
			apitypes.CommandStatusRunning,
			now.Format(time.RFC3339Nano),
			leaseUntil.Format(time.RFC3339Nano),
			cmd.ID,
			apitypes.CommandStatusQueued,
		)
		if err != nil {
			return nil, err
		}
		cmd.Status = apitypes.CommandStatusRunning
		st := now
		lu := leaseUntil
		cmd.StartedAt = &st
		cmd.LeaseUntil = &lu
		// Never return api_key to logs via accidental dump; keep for execution.
		out = append(out, cmd)
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return out, nil
}

func (s *SQLiteStore) CompleteCommand(id string, req apitypes.CommandResultRequest) (apitypes.MachineCommand, error) {
	status, err := sanitizeResultStatus(req.Status)
	if err != nil {
		return apitypes.MachineCommand{}, err
	}
	if strings.TrimSpace(id) == "" {
		return apitypes.MachineCommand{}, fmt.Errorf("command id required")
	}
	if strings.TrimSpace(req.MachineID) == "" {
		return apitypes.MachineCommand{}, fmt.Errorf("machine_id required")
	}

	now := time.Now().UTC()
	_ = s.ExpireCommands(now)

	tx, err := s.db.Begin()
	if err != nil {
		return apitypes.MachineCommand{}, err
	}
	defer func() { _ = tx.Rollback() }()

	cmd, err := loadCommandTx(tx, id)
	if err != nil {
		return apitypes.MachineCommand{}, err
	}
	if cmd.MachineID != req.MachineID {
		return apitypes.MachineCommand{}, fmt.Errorf("machine_id mismatch")
	}
	if apitypes.CommandTerminal(cmd.Status) {
		return cmd, nil
	}
	if cmd.Status != apitypes.CommandStatusRunning && cmd.Status != apitypes.CommandStatusQueued {
		return apitypes.MachineCommand{}, fmt.Errorf("command not completable in status %s", cmd.Status)
	}

	cmd.Payload = stripAPIKey(cmd.Payload)
	payloadRaw, err := json.Marshal(cmd.Payload)
	if err != nil {
		return apitypes.MachineCommand{}, err
	}
	errMsg := strings.TrimSpace(req.ErrorMessage)
	if len(errMsg) > 500 {
		errMsg = errMsg[:500]
	}
	_, err = tx.Exec(`
UPDATE machine_commands
SET status=?, error_message=?, finished_at=?, payload_json=?, lease_until=NULL
WHERE id=?`,
		status, errMsg, now.Format(time.RFC3339Nano), string(payloadRaw), id)
	if err != nil {
		return apitypes.MachineCommand{}, err
	}
	if err := tx.Commit(); err != nil {
		return apitypes.MachineCommand{}, err
	}

	cmd.Status = status
	cmd.ErrorMessage = errMsg
	ft := now
	cmd.FinishedAt = &ft
	cmd.LeaseUntil = nil

	if req.ProvidersReport != nil {
		report := *req.ProvidersReport
		// Bind snapshot to the command's machine; never allow cross-machine overwrite.
		report.MachineID = req.MachineID
		_ = s.ApplyProvidersReport(report)
	}
	return cmd, nil
}

func (s *SQLiteStore) GetCommand(id string) (apitypes.MachineCommand, error) {
	_ = s.ExpireCommands(time.Now().UTC())
	row := s.db.QueryRow(`
SELECT id, machine_id, app, type, payload_json, status, error_message,
       created_at, started_at, finished_at, lease_until
FROM machine_commands WHERE id=?`, id)
	cmd, err := scanCommandFull(row)
	if err == sql.ErrNoRows {
		return apitypes.MachineCommand{}, fmt.Errorf("command not found")
	}
	if err != nil {
		return apitypes.MachineCommand{}, err
	}
	// Never expose api_key to App.
	cmd.Payload = stripAPIKey(cmd.Payload)
	return cmd, nil
}

func (s *SQLiteStore) ExpireCommands(now time.Time) int {
	if now.IsZero() {
		now = time.Now().UTC()
	}
	queuedCut := now.Add(-time.Duration(CommandQueuedTimeoutSec) * time.Second)
	runningCut := now.Add(-time.Duration(CommandRunningTimeoutSec) * time.Second)
	n := 0

	res, err := s.db.Exec(`
UPDATE machine_commands
SET status=?, error_message=?, finished_at=?, payload_json=json_set(COALESCE(payload_json,'{}'), '$.api_key', '')
WHERE status=? AND created_at < ?`,
		apitypes.CommandStatusTimedOut, "queued timeout", now.Format(time.RFC3339Nano),
		apitypes.CommandStatusQueued, queuedCut.Format(time.RFC3339Nano))
	if err == nil {
		if c, _ := res.RowsAffected(); c > 0 {
			n += int(c)
		}
	}
	// Fallback without json_set if SQLite build lacks it — retry simple update.
	if err != nil {
		res, err = s.db.Exec(`
UPDATE machine_commands
SET status=?, error_message=?, finished_at=?
WHERE status=? AND created_at < ?`,
			apitypes.CommandStatusTimedOut, "queued timeout", now.Format(time.RFC3339Nano),
			apitypes.CommandStatusQueued, queuedCut.Format(time.RFC3339Nano))
		if err == nil {
			if c, _ := res.RowsAffected(); c > 0 {
				n += int(c)
			}
		}
	}

	res, err = s.db.Exec(`
UPDATE machine_commands
SET status=?, error_message=?, finished_at=?, lease_until=NULL
WHERE status=? AND (
  (started_at IS NOT NULL AND started_at < ?)
  OR (lease_until IS NOT NULL AND lease_until < ?)
)`,
		apitypes.CommandStatusTimedOut, "running timeout", now.Format(time.RFC3339Nano),
		apitypes.CommandStatusRunning,
		runningCut.Format(time.RFC3339Nano),
		now.Format(time.RFC3339Nano),
	)
	if err == nil {
		if c, _ := res.RowsAffected(); c > 0 {
			n += int(c)
		}
	}
	// Strip keys from timed-out rows best-effort (payload may still hold key until next complete).
	_ = s.stripTimedOutKeys()
	return n
}

func (s *SQLiteStore) stripTimedOutKeys() error {
	rows, err := s.db.Query(`
SELECT id, payload_json FROM machine_commands
WHERE status=? AND payload_json LIKE '%api_key%'`, apitypes.CommandStatusTimedOut)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var id, payload string
		if err := rows.Scan(&id, &payload); err != nil {
			continue
		}
		var p apitypes.CommandPayload
		if err := json.Unmarshal([]byte(payload), &p); err != nil {
			continue
		}
		if p.APIKey == "" {
			continue
		}
		p.APIKey = ""
		raw, _ := json.Marshal(p)
		_, _ = s.db.Exec(`UPDATE machine_commands SET payload_json=? WHERE id=?`, string(raw), id)
	}
	return nil
}

type rowScanner interface {
	Scan(dest ...interface{}) error
}

func loadCommandTx(tx *sql.Tx, id string) (apitypes.MachineCommand, error) {
	row := tx.QueryRow(`
SELECT id, machine_id, app, type, payload_json, status, error_message,
       created_at, started_at, finished_at, lease_until
FROM machine_commands WHERE id=?`, id)
	cmd, err := scanCommandFull(row)
	if err == sql.ErrNoRows {
		return apitypes.MachineCommand{}, fmt.Errorf("command not found")
	}
	return cmd, err
}

func scanCommandRow(rows *sql.Rows) (apitypes.MachineCommand, error) {
	var (
		cmd                      apitypes.MachineCommand
		payload, created, status string
		errMsg                   string
	)
	if err := rows.Scan(&cmd.ID, &cmd.MachineID, &cmd.App, &cmd.Type, &payload, &status, &errMsg, &created); err != nil {
		return cmd, err
	}
	_ = json.Unmarshal([]byte(payload), &cmd.Payload)
	cmd.Status = status
	cmd.ErrorMessage = errMsg
	if t, err := time.Parse(time.RFC3339Nano, created); err == nil {
		cmd.CreatedAt = t
	}
	return cmd, nil
}

func scanCommandFull(row rowScanner) (apitypes.MachineCommand, error) {
	var (
		cmd                              apitypes.MachineCommand
		payload, status, errMsg, created string
		started, finished, lease         sql.NullString
	)
	if err := row.Scan(
		&cmd.ID, &cmd.MachineID, &cmd.App, &cmd.Type, &payload, &status, &errMsg,
		&created, &started, &finished, &lease,
	); err != nil {
		return cmd, err
	}
	_ = json.Unmarshal([]byte(payload), &cmd.Payload)
	cmd.Status = status
	cmd.ErrorMessage = errMsg
	if t, err := time.Parse(time.RFC3339Nano, created); err == nil {
		cmd.CreatedAt = t
	}
	if started.Valid {
		if t, err := time.Parse(time.RFC3339Nano, started.String); err == nil {
			cmd.StartedAt = &t
		}
	}
	if finished.Valid {
		if t, err := time.Parse(time.RFC3339Nano, finished.String); err == nil {
			cmd.FinishedAt = &t
		}
	}
	if lease.Valid {
		if t, err := time.Parse(time.RFC3339Nano, lease.String); err == nil {
			cmd.LeaseUntil = &t
		}
	}
	return cmd, nil
}
