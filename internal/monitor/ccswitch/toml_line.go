package ccswitch

import (
	"regexp"
	"strings"
)

// tomlGet returns the first assignment value for key (quoted or bare).
// For base_url it prefers the first match anywhere (usually under model_providers).
func tomlGet(cfg, key string) string {
	if cfg == "" || key == "" {
		return ""
	}
	re := regexp.MustCompile(`(?m)^\s*` + regexp.QuoteMeta(key) + `\s*=\s*(.+?)\s*$`)
	m := re.FindStringSubmatch(cfg)
	if len(m) < 2 {
		return ""
	}
	return unquoteTOML(strings.TrimSpace(m[1]))
}

// tomlSet replaces the first assignment for key, or inserts at top when missing.
// Only touches the first matching line to avoid rewriting unrelated sections.
func tomlSet(cfg, key, value string) string {
	if key == "" {
		return cfg
	}
	quoted := quoteTOML(value)
	re := regexp.MustCompile(`(?m)^(\s*)` + regexp.QuoteMeta(key) + `\s*=\s*.*$`)
	if re.MatchString(cfg) {
		return re.ReplaceAllString(cfg, `${1}`+key+` = `+quoted)
	}
	line := key + " = " + quoted
	if strings.TrimSpace(cfg) == "" {
		return line + "\n"
	}
	if strings.HasSuffix(cfg, "\n") {
		return line + "\n" + cfg
	}
	return line + "\n" + cfg
}

func unquoteTOML(v string) string {
	v = strings.TrimSpace(v)
	if len(v) >= 2 {
		if (v[0] == '"' && v[len(v)-1] == '"') || (v[0] == '\'' && v[len(v)-1] == '\'') {
			inner := v[1 : len(v)-1]
			inner = strings.ReplaceAll(inner, `\"`, `"`)
			return inner
		}
	}
	// strip trailing comments
	if i := strings.Index(v, " #"); i >= 0 {
		v = strings.TrimSpace(v[:i])
	}
	return v
}

func quoteTOML(v string) string {
	v = strings.ReplaceAll(v, `\`, `\\`)
	v = strings.ReplaceAll(v, `"`, `\"`)
	return `"` + v + `"`
}
