package auth

import (
	"net/http"
	"strings"
)

// Check validates Authorization: Bearer <key> or X-Agent-Status-Key.
func Check(r *http.Request, key string) bool {
	if key == "" {
		return false
	}
	if h := r.Header.Get("X-Agent-Status-Key"); h != "" {
		return h == key
	}
	authz := r.Header.Get("Authorization")
	if strings.HasPrefix(authz, "Bearer ") {
		return strings.TrimPrefix(authz, "Bearer ") == key
	}
	// query only for WS debug: ?key=
	if q := r.URL.Query().Get("key"); q != "" {
		return q == key
	}
	return false
}
