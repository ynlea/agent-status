package monitor

import (
	"strings"
	"unicode"
	"unicode/utf8"
)

const defaultSummaryRunes = 48

// ShortSummary builds a privacy-safe one-line task summary from user text.
// Empty input returns empty string; callers fall back to status labels.
func ShortSummary(text string, maxRunes int) string {
	if maxRunes <= 0 {
		maxRunes = defaultSummaryRunes
	}
	text = strings.TrimSpace(text)
	if text == "" {
		return ""
	}
	if i := strings.IndexByte(text, '\n'); i >= 0 {
		text = text[:i]
	}
	if i := strings.IndexByte(text, '\r'); i >= 0 {
		text = text[:i]
	}
	text = strings.TrimSpace(text)
	if text == "" {
		return ""
	}
	var b strings.Builder
	b.Grow(len(text))
	prevSpace := false
	for _, r := range text {
		if unicode.IsSpace(r) {
			if prevSpace {
				continue
			}
			b.WriteByte(' ')
			prevSpace = true
			continue
		}
		prevSpace = false
		b.WriteRune(r)
	}
	text = strings.TrimSpace(b.String())
	if text == "" {
		return ""
	}
	if utf8.RuneCountInString(text) <= maxRunes {
		return text
	}
	runes := []rune(text)
	if maxRunes == 1 {
		return "…"
	}
	return string(runes[:maxRunes-1]) + "…"
}

// preferMessage keeps an existing task summary when the next value is only a status label.
func preferMessage(prev, next string) string {
	next = strings.TrimSpace(next)
	if next == "" {
		return prev
	}
	if prev != "" && isGenericStatusMessage(next) {
		return prev
	}
	return next
}

func isGenericStatusMessage(msg string) bool {
	msg = strings.TrimSpace(msg)
	switch msg {
	case "stopped", "permission request", "notification",
		"user_message", "task_started", "task_complete", "turn_aborted",
		"turn_started", "turn_completed", "interrupted", "failed", "idle",
		"exec_approval_request", "apply_patch_approval_request",
		"request_user_input", "user_input_request", "elicitation_request":
		return true
	}
	// Event / tool tokens: ascii labels like task_complete or function_call:bash
	if msg == "" || utf8.RuneCountInString(msg) > 48 {
		return false
	}
	hasASCIILetter := false
	for _, r := range msg {
		if r > unicode.MaxASCII {
			return false
		}
		if r == ' ' {
			return false
		}
		if r == '_' || r == '-' || r == ':' || r == '.' {
			continue
		}
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') {
			hasASCIILetter = true
			continue
		}
		if r >= '0' && r <= '9' {
			continue
		}
		return false
	}
	return hasASCIILetter
}
