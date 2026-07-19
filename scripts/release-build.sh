#!/usr/bin/env bash
# Build Release assets for agent-status (server + monitor).
# Usage: ./scripts/release-build.sh [output-dir]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-"$ROOT/dist/release"}"
mkdir -p "$OUT"

export PATH="${HOME}/.local/go/bin:${PATH:-}"
if ! command -v go >/dev/null 2>&1; then
  echo "go not found in PATH" >&2
  exit 1
fi

build_one() {
  local goos="$1" goarch="$2" bin="$3" pkg="$4"
  local ext=""
  if [[ "$goos" == "windows" ]]; then
    ext=".exe"
  fi
  local name="${bin}-${goos}-${goarch}${ext}"
  echo "building $name"
  (
    cd "$ROOT"
    CGO_ENABLED=0 GOOS="$goos" GOARCH="$goarch" go build -trimpath -ldflags="-s -w" -o "$OUT/$name" "$pkg"
  )
}

build_one linux amd64 agent-status-server ./cmd/server
build_one linux arm64 agent-status-server ./cmd/server
build_one linux amd64 agent-status-monitor ./cmd/monitor
build_one linux arm64 agent-status-monitor ./cmd/monitor
build_one windows amd64 agent-status-server ./cmd/server
build_one windows amd64 agent-status-monitor ./cmd/monitor

(
  cd "$OUT"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum agent-status-* >sha256sums.txt
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 agent-status-* >sha256sums.txt
  else
    echo "warning: no sha256 tool; skip sha256sums.txt" >&2
  fi
)

echo "done: $OUT"
ls -la "$OUT"
