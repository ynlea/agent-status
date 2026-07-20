package monitor

import (
	"bufio"
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/ynlea/agent-status/pkg/apitypes"
)

// ParseClaudeUsageFile reads assistant usage lines from a Claude session JSONL.
// fromOffset is a byte offset; returns newly found events and the end offset.
func ParseClaudeUsageFile(path string, fromOffset int64) (events []apitypes.UsageEvent, newOffset int64, err error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fromOffset, err
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil {
		return nil, fromOffset, err
	}
	size := info.Size()
	if fromOffset > size {
		fromOffset = 0
	}
	if fromOffset > 0 {
		if _, err := f.Seek(fromOffset, io.SeekStart); err != nil {
			return nil, fromOffset, err
		}
	}
	seen := map[string]struct{}{}
	r := bufio.NewReader(f)
	var pos = fromOffset
	for {
		line, err := r.ReadString('\n')
		if len(line) > 0 {
			pos += int64(len(line))
			trim := strings.TrimSpace(line)
			if trim != "" {
				if ev, ok := parseClaudeLine(trim, path); ok {
					if _, dup := seen[ev.DedupeKey]; !dup {
						seen[ev.DedupeKey] = struct{}{}
						events = append(events, ev)
					}
				}
			}
		}
		if err == io.EOF {
			// incomplete trailing line without newline: do not advance past it
			if !strings.HasSuffix(line, "\n") && len(line) > 0 {
				pos -= int64(len(line))
			}
			break
		}
		if err != nil {
			return events, pos, err
		}
	}
	return events, pos, nil
}

func parseClaudeLine(line, path string) (apitypes.UsageEvent, bool) {
	var rec map[string]interface{}
	if err := json.Unmarshal([]byte(line), &rec); err != nil {
		return apitypes.UsageEvent{}, false
	}
	typ, _ := rec["type"].(string)
	msg, _ := rec["message"].(map[string]interface{})
	if typ != "assistant" && (msg == nil || strField(msg, "role") != "assistant") {
		// still allow usage nested under message without type
		if msg == nil {
			return apitypes.UsageEvent{}, false
		}
	}
	usage := mapField(msg, "usage")
	if usage == nil {
		usage, _ = rec["usage"].(map[string]interface{})
	}
	if usage == nil {
		return apitypes.UsageEvent{}, false
	}
	in := int64Field(usage, "input_tokens")
	out := int64Field(usage, "output_tokens")
	cw := int64Field(usage, "cache_creation_input_tokens")
	if cw == 0 {
		if cc := mapField(usage, "cache_creation"); cc != nil {
			cw = int64Field(cc, "ephemeral_5m_input_tokens") + int64Field(cc, "ephemeral_1h_input_tokens")
		}
	}
	ch := int64Field(usage, "cache_read_input_tokens")
	if in == 0 && out == 0 && cw == 0 && ch == 0 {
		return apitypes.UsageEvent{}, false
	}
	model := strField(msg, "model")
	if model == "" {
		model = strField(rec, "model")
	}
	if model == "" {
		model = "unknown"
	}
	mid := strField(msg, "id")
	if mid == "" {
		mid = strField(rec, "uuid")
	}
	if mid == "" {
		// fallback: path + timestamp + totals
		mid = filepath.Base(path) + ":" + strField(rec, "timestamp") + ":" + itoa(in) + ":" + itoa(out)
	}
	at := parseTimeField(rec, "timestamp")
	if at.IsZero() {
		at = time.Now().UTC()
	}
	sid := strField(rec, "sessionId")
	if sid == "" {
		sid = strings.TrimSuffix(filepath.Base(path), ".jsonl")
	}
	return apitypes.UsageEvent{
		DedupeKey:        "claude:" + mid,
		Agent:            "claude",
		Model:            model,
		SessionID:        sid,
		OccurredAt:       at,
		InputTokens:      in,
		OutputTokens:     out,
		CacheWriteTokens: cw,
		CacheHitTokens:   ch,
	}, true
}

// ParseCodexUsageFile reads token_count events from a Codex rollout JSONL.
// startModel is the last known model from a previous cursor (empty → "unknown").
// When fromOffset > 0 and startModel is empty/unknown, the file prefix is scanned
// for the latest turn_context model so mid-file ticks do not emit "unknown".
func ParseCodexUsageFile(path string, fromOffset int64, startModel string) (events []apitypes.UsageEvent, newOffset int64, lastModel string, err error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fromOffset, startModel, err
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil {
		return nil, fromOffset, startModel, err
	}
	size := info.Size()
	if fromOffset > size {
		fromOffset = 0
	}

	model := strings.TrimSpace(startModel)
	if model == "" {
		model = "unknown"
	}
	// Incremental reads start mid-file; recover model from prefix if needed.
	if fromOffset > 0 && isUnknownModel(model) {
		if m, ok := recoverCodexModelPrefix(f, fromOffset); ok {
			model = m
		}
		if _, err := f.Seek(fromOffset, io.SeekStart); err != nil {
			return nil, fromOffset, model, err
		}
	} else if fromOffset > 0 {
		if _, err := f.Seek(fromOffset, io.SeekStart); err != nil {
			return nil, fromOffset, model, err
		}
	}

	var prevTotal map[string]int64
	r := bufio.NewReader(f)
	var pos = fromOffset
	for {
		line, err := r.ReadString('\n')
		if len(line) > 0 {
			pos += int64(len(line))
			trim := strings.TrimSpace(line)
			if trim == "" {
				goto next
			}
			var rec map[string]interface{}
			if json.Unmarshal([]byte(trim), &rec) != nil {
				goto next
			}
			typ, _ := rec["type"].(string)
			payload := mapField(rec, "payload")
			switch typ {
			case "session_meta":
				// ok
			case "turn_context":
				if m := codexModelFromPayload(payload); m != "" {
					model = m
				}
			case "event_msg":
				if strField(payload, "type") != "token_count" {
					break
				}
				infoM := mapField(payload, "info")
				if infoM == nil {
					break
				}
				last := mapField(infoM, "last_token_usage")
				total := mapField(infoM, "total_token_usage")
				usage := last
				if usage == nil && total != nil {
					usage = deltaUsageFromPrev(total, prevTotal)
				}
				if total != nil {
					prevTotal = intMap(total)
				}
				if usage == nil {
					break
				}
				if m := strField(infoM, "model"); m != "" {
					model = m
				}
				rawIn := int64Field(usage, "input_tokens")
				cached := int64Field(usage, "cached_input_tokens")
				if cached == 0 {
					cached = int64Field(usage, "cache_read_input_tokens")
				}
				out := int64Field(usage, "output_tokens")
				reason := int64Field(usage, "reasoning_output_tokens")
				if rawIn < 0 || out < 0 || cached < 0 || reason < 0 {
					break
				}
				billed := rawIn - cached
				if billed < 0 {
					billed = 0
				}
				if billed == 0 && out == 0 && reason == 0 && cached == 0 {
					break
				}
				at := parseTimeField(rec, "timestamp")
				if at.IsZero() {
					at = time.Now().UTC()
				}
				// stable-ish dedupe across re-reads
				totIn := int64Field(total, "input_tokens")
				totOut := int64Field(total, "output_tokens")
				key := "codex:" + filepath.Base(path) + ":" + at.UTC().Format(time.RFC3339Nano) + ":" + itoa(totIn) + "+" + itoa(totOut)
				if total == nil {
					key = "codex:" + filepath.Base(path) + ":" + at.UTC().Format(time.RFC3339Nano) + ":" + itoa(rawIn) + "+" + itoa(out)
				}
				sid := strings.TrimSuffix(strings.TrimPrefix(filepath.Base(path), "rollout-"), ".jsonl")
				events = append(events, apitypes.UsageEvent{
					DedupeKey:       key,
					Agent:           "codex",
					Model:           model,
					SessionID:       sid,
					OccurredAt:      at,
					InputTokens:     billed,
					OutputTokens:    out,
					ReasoningTokens: reason,
					CacheHitTokens:  cached,
				})
			}
		}
	next:
		if err == io.EOF {
			if !strings.HasSuffix(line, "\n") && len(line) > 0 {
				pos -= int64(len(line))
			}
			break
		}
		if err != nil {
			return events, pos, model, err
		}
	}
	return events, pos, model, nil
}

func isUnknownModel(m string) bool {
	m = strings.TrimSpace(m)
	return m == "" || strings.EqualFold(m, "unknown")
}

func codexModelFromPayload(payload map[string]interface{}) string {
	if m := strField(payload, "model"); m != "" {
		return m
	}
	if ts := mapField(payload, "thread_settings"); ts != nil {
		if m := strField(ts, "model"); m != "" {
			return m
		}
		if cm := mapField(ts, "collaboration_mode"); cm != nil {
			if settings := mapField(cm, "settings"); settings != nil {
				if m := strField(settings, "model"); m != "" {
					return m
				}
			}
		}
	}
	if cm := mapField(payload, "collaboration_mode"); cm != nil {
		if settings := mapField(cm, "settings"); settings != nil {
			if m := strField(settings, "model"); m != "" {
				return m
			}
		}
	}
	return ""
}

// recoverCodexModelPrefix scans [0, until) for the last turn_context model.
func recoverCodexModelPrefix(f *os.File, until int64) (string, bool) {
	if until <= 0 {
		return "", false
	}
	if _, err := f.Seek(0, io.SeekStart); err != nil {
		return "", false
	}
	r := bufio.NewReader(f)
	var pos int64
	model := ""
	for pos < until {
		line, err := r.ReadString('\n')
		if len(line) == 0 && err != nil {
			break
		}
		pos += int64(len(line))
		if pos > until {
			// line crossed the cursor boundary; ignore this incomplete-at-cursor line
			break
		}
		trim := strings.TrimSpace(line)
		if trim == "" {
			if err != nil {
				break
			}
			continue
		}
		var rec map[string]interface{}
		if json.Unmarshal([]byte(trim), &rec) != nil {
			if err != nil {
				break
			}
			continue
		}
		if typ, _ := rec["type"].(string); typ == "turn_context" {
			if m := codexModelFromPayload(mapField(rec, "payload")); m != "" {
				model = m
			}
		}
		if err != nil {
			break
		}
	}
	if model == "" {
		return "", false
	}
	return model, true
}

func intMap(m map[string]interface{}) map[string]int64 {
	out := map[string]int64{}
	for k := range m {
		out[k] = int64Field(m, k)
	}
	return out
}

func deltaUsageFromPrev(total map[string]interface{}, prev map[string]int64) map[string]interface{} {
	if prev == nil {
		return total
	}
	out := map[string]interface{}{}
	for _, k := range []string{"input_tokens", "output_tokens", "cached_input_tokens", "cache_read_input_tokens", "reasoning_output_tokens", "total_tokens"} {
		t := int64Field(total, k)
		d := t - prev[k]
		if d < 0 {
			return total
		}
		out[k] = d
	}
	return out
}

func mapField(m map[string]interface{}, key string) map[string]interface{} {
	if m == nil {
		return nil
	}
	v, _ := m[key].(map[string]interface{})
	return v
}

func strField(m map[string]interface{}, key string) string {
	if m == nil {
		return ""
	}
	switch v := m[key].(type) {
	case string:
		return v
	default:
		return ""
	}
}

func int64Field(m map[string]interface{}, key string) int64 {
	if m == nil {
		return 0
	}
	switch v := m[key].(type) {
	case float64:
		return int64(v)
	case int64:
		return v
	case int:
		return int64(v)
	case json.Number:
		n, _ := v.Int64()
		return n
	case string:
		n, _ := strconv.ParseInt(v, 10, 64)
		return n
	default:
		return 0
	}
}

func parseTimeField(m map[string]interface{}, key string) time.Time {
	if m == nil {
		return time.Time{}
	}
	switch v := m[key].(type) {
	case string:
		if t, err := time.Parse(time.RFC3339Nano, v); err == nil {
			return t.UTC()
		}
		if t, err := time.Parse(time.RFC3339, v); err == nil {
			return t.UTC()
		}
	case float64:
		// seconds or ms
		if v > 1e12 {
			return time.UnixMilli(int64(v)).UTC()
		}
		return time.Unix(int64(v), 0).UTC()
	}
	return time.Time{}
}

func itoa(n int64) string {
	return strconv.FormatInt(n, 10)
}

// CollectClaudeUsageFiles lists session jsonl under projects dir.
func CollectClaudeUsageFiles(projectsDir string) ([]string, error) {
	var out []string
	if projectsDir == "" {
		return out, nil
	}
	err := filepath.Walk(projectsDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil
		}
		if info.IsDir() {
			return nil
		}
		if strings.HasSuffix(info.Name(), ".jsonl") {
			out = append(out, path)
		}
		return nil
	})
	return out, err
}

// CollectCodexUsageFiles lists rollout jsonl under sessions + archived.
func CollectCodexUsageFiles(sessionsDir string) ([]string, error) {
	var out []string
	roots := []string{sessionsDir}
	// sibling archived_sessions
	if sessionsDir != "" {
		roots = append(roots, filepath.Join(filepath.Dir(sessionsDir), "archived_sessions"))
	}
	for _, root := range roots {
		_ = filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
			if err != nil || info == nil || info.IsDir() {
				return nil
			}
			name := info.Name()
			if strings.HasPrefix(name, "rollout-") && strings.HasSuffix(name, ".jsonl") {
				out = append(out, path)
			}
			return nil
		})
	}
	return out, nil
}
