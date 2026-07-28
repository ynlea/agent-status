package monitor

import (
	"bufio"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// codexTokenSig is a stable fingerprint of one token_count row for parent/child
// replay matching (aligned with cc-switch TokenUsageSignature spirit).
type codexTokenSig struct {
	In, Cached, Out, Reason, Tot int64
	HasTotal                     bool
	HasLast                      bool
}

func codexTokenSigFromInfo(info map[string]interface{}) (codexTokenSig, bool) {
	if info == nil {
		return codexTokenSig{}, false
	}
	total := mapField(info, "total_token_usage")
	last := mapField(info, "last_token_usage")
	if total == nil && last == nil {
		return codexTokenSig{}, false
	}
	var s codexTokenSig
	if total != nil {
		s.HasTotal = true
		s.In = int64Field(total, "input_tokens")
		s.Cached = int64Field(total, "cached_input_tokens")
		if s.Cached == 0 {
			s.Cached = int64Field(total, "cache_read_input_tokens")
		}
		s.Out = int64Field(total, "output_tokens")
		s.Reason = int64Field(total, "reasoning_output_tokens")
		s.Tot = int64Field(total, "total_tokens")
	}
	if last != nil {
		s.HasLast = true
		// When total missing, fingerprint last; when both present, total already set.
		if total == nil {
			s.In = int64Field(last, "input_tokens")
			s.Cached = int64Field(last, "cached_input_tokens")
			if s.Cached == 0 {
				s.Cached = int64Field(last, "cache_read_input_tokens")
			}
			s.Out = int64Field(last, "output_tokens")
			s.Reason = int64Field(last, "reasoning_output_tokens")
			s.Tot = int64Field(last, "total_tokens")
		}
	}
	return s, true
}

type codexRolloutMeta struct {
	ThreadID       string
	ParentThreadID string
	IsSubagent     bool
	RootTimestamp  time.Time
}

func readCodexRolloutMeta(path string) codexRolloutMeta {
	var meta codexRolloutMeta
	// Filename UUID is the durable thread id used by monitor SessionID stem rules.
	base := filepath.Base(path)
	stem := strings.TrimSuffix(strings.TrimPrefix(base, "rollout-"), ".jsonl")
	if i := strings.LastIndex(stem, "-"); i >= 0 && len(stem)-i-1 >= 36 {
		// rollout-TIME-UUID → UUID may contain dashes; take last 36 chars if valid-ish
		cand := stem[len(stem)-36:]
		if strings.Count(cand, "-") == 4 {
			meta.ThreadID = cand
		}
	}
	f, err := os.Open(path)
	if err != nil {
		return meta
	}
	defer f.Close()
	r := bufio.NewReader(f)
	for {
		line, err := r.ReadString('\n')
		trim := strings.TrimSpace(line)
		if trim != "" {
			var rec map[string]interface{}
			if json.Unmarshal([]byte(trim), &rec) == nil {
				if typ, _ := rec["type"].(string); typ == "session_meta" {
					payload := mapField(rec, "payload")
					if id := strField(payload, "id"); id != "" {
						meta.ThreadID = id
					}
					if ts := parseTimeField(rec, "timestamp"); !ts.IsZero() {
						meta.RootTimestamp = ts
					}
					parent := strField(payload, "parent_thread_id")
					if parent == "" {
						parent = strField(payload, "forked_from_id")
					}
					if parent == "" {
						if src := mapField(payload, "source"); src != nil {
							if sub := mapField(src, "subagent"); sub != nil {
								if spawn := mapField(sub, "thread_spawn"); spawn != nil {
									parent = strField(spawn, "parent_thread_id")
								}
								meta.IsSubagent = true
							}
						}
					}
					if ts := strField(payload, "thread_source"); strings.EqualFold(strings.TrimSpace(ts), "subagent") {
						meta.IsSubagent = true
					}
					if parent != "" {
						meta.ParentThreadID = parent
						meta.IsSubagent = true
					}
				}
			}
		}
		if err != nil {
			break
		}
	}
	return meta
}

func collectCodexTokenSigs(path string, before time.Time) []codexTokenSig {
	f, err := os.Open(path)
	if err != nil {
		return nil
	}
	defer f.Close()
	var out []codexTokenSig
	r := bufio.NewReader(f)
	for {
		line, err := r.ReadString('\n')
		trim := strings.TrimSpace(line)
		if trim != "" {
			var rec map[string]interface{}
			if json.Unmarshal([]byte(trim), &rec) == nil {
				if typ, _ := rec["type"].(string); typ == "event_msg" {
					payload := mapField(rec, "payload")
					if strField(payload, "type") == "token_count" {
						skip := false
						if !before.IsZero() {
							ts := parseTimeField(rec, "timestamp")
							// parent sigs only up to child fork time
							if !ts.IsZero() && ts.After(before) {
								skip = true
							}
						}
						if !skip {
							if sig, ok := codexTokenSigFromInfo(mapField(payload, "info")); ok {
								out = append(out, sig)
							}
						}
					}
				}
			}
		}
		if err != nil {
			break
		}
	}
	return out
}

// matchingCodexReplayPrefix returns how many leading child token_count rows match
// the parent signature sequence (cc-switch matching_replay_prefix).
func matchingCodexReplayPrefix(child, parent []codexTokenSig) int {
	if len(child) == 0 || len(parent) == 0 {
		return 0
	}
	parentOffset := 0
	matched := 0
	for _, ev := range child {
		found := -1
		for i := parentOffset; i < len(parent); i++ {
			if parent[i] == ev {
				found = i
				break
			}
		}
		if found < 0 {
			break
		}
		parentOffset = found + 1
		matched++
	}
	return matched
}

// codexReplaySkipCount computes how many leading token_count events to process
// only as baseline (no UsageEvent) for a subagent rollout.
func codexReplaySkipCount(path string, rootIndex map[string]string) int {
	meta := readCodexRolloutMeta(path)
	if !meta.IsSubagent || meta.ParentThreadID == "" {
		return 0
	}
	parentPath := rootIndex[meta.ParentThreadID]
	if parentPath == "" {
		return 0
	}
	parentSigs := collectCodexTokenSigs(parentPath, meta.RootTimestamp)
	childSigs := collectCodexTokenSigs(path, time.Time{})
	return matchingCodexReplayPrefix(childSigs, parentSigs)
}

// buildCodexRootRolloutIndex maps root thread id → rollout path (non-subagent preferred).
func buildCodexRootRolloutIndex(paths []string) map[string]string {
	out := make(map[string]string, len(paths))
	type cand struct {
		path string
		sub  bool
	}
	best := map[string]cand{}
	for _, p := range paths {
		meta := readCodexRolloutMeta(p)
		id := meta.ThreadID
		if id == "" {
			continue
		}
		prev, ok := best[id]
		if !ok || (prev.sub && !meta.IsSubagent) {
			best[id] = cand{path: p, sub: meta.IsSubagent}
		}
	}
	for id, c := range best {
		if !c.sub {
			out[id] = c.path
		}
	}
	// Also index by filename UUID for parent_thread_id that equals file stem uuid.
	for _, p := range paths {
		meta := readCodexRolloutMeta(p)
		if meta.IsSubagent || meta.ThreadID == "" {
			continue
		}
		out[meta.ThreadID] = p
	}
	return out
}
