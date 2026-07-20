#!/usr/bin/env bash
# agent-status 安装与本机管理（Linux）
# 交互：curl -fsSL .../install.sh | bash
# 非交互示例：
#   ./install.sh install --role server --key KEY --yes
#   ./install.sh install --role monitor --server-url URL --key KEY --yes
#   ./install.sh status|start|stop|restart --role all
set -euo pipefail

REPO="${AGENT_STATUS_REPO:-ynlea/agent-status}"
RELEASE_API="https://api.github.com/repos/${REPO}/releases"
RAW_BASE="https://raw.githubusercontent.com/${REPO}"
INSTALL_ROOT="${AGENT_STATUS_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/agent-status}"
BIN_DIR="$INSTALL_ROOT/bin"
CONFIG_DIR="$INSTALL_ROOT/config"
DATA_DIR="$INSTALL_ROOT/data"
LOG_DIR="$INSTALL_ROOT/logs"
STATE_DIR="$INSTALL_ROOT/state"
SYSTEMD_USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
LOCAL_BIN="${AGENT_STATUS_LOCAL_BIN:-$HOME/.local/bin}"

CMD="install"
ROLE=""
YES=0
VERSION="latest"
SERVER_URL=""
KEY=""
ADDR=":29125"
NO_INIT_AGENTS=0
NO_ENABLE=0
LOCAL_BIN_SRC=""
FORCE_CONFIG=0
PURGE=0
CONFIG_ACTION=""
CONFIG_KV=()

usage() {
  cat <<'EOF'
agent-status 安装与管理工具（Linux）

用法：
  install.sh [命令] [选项]

命令：
  install（默认）     安装或升级
  update              更新二进制（停服→下载→启动，保留配置）
  status              查看状态
  start|stop|restart  启停服务
  enable|disable      开机自启（systemd --user）
  config get|set      查看或更新配置
  init-agents         探测本机 Agent 并初始化 Claude hooks
  uninstall           停止服务；默认保留配置，加 --purge 删除安装目录

选项：
  --role server|monitor|all
  --yes, -y           非交互，跳过确认
  --version TAG|latest
  --server-url URL    监测端上报地址
  --key KEY           预共享密钥
  --addr ADDR         服务端监听地址
  --no-init-agents    跳过 Agent 初始化
  --no-enable         不安自启（仍会尝试启动）
  --local-bin DIR     使用本地二进制，跳过下载
  --force-config      安装时覆盖已有配置
  --purge             卸载时删除安装目录
  -h, --help
EOF
}

# --- UI (ANSI colors when TTY) ---
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_CYAN=$'\033[36m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'
  C_MAGENTA=$'\033[35m'
  C_BLUE=$'\033[34m'
  C_WHITE=$'\033[97m'
  C_BG=$'\033[48;5;236m'
  # 256-color accents
  C_A1=$'\033[38;5;51m'    # bright cyan
  C_A2=$'\033[38;5;45m'
  C_A3=$'\033[38;5;39m'
  C_A4=$'\033[38;5;33m'
  C_A5=$'\033[38;5;99m'    # purple
else
  C_RESET= C_BOLD= C_DIM= C_CYAN= C_GREEN= C_YELLOW= C_RED= C_MAGENTA= C_BLUE= C_WHITE= C_BG=
  C_A1= C_A2= C_A3= C_A4= C_A5=
fi

UI_STEP_CUR=0
UI_STEP_TOTAL=0
UI_WIDTH=54

log()  { printf '%s\n' "$*"; }
info() { printf '  %s›%s  %s\n' "${C_A2}" "${C_RESET}" "$*"; }
ok()   { printf '  %s✓%s  %s\n' "${C_GREEN}${C_BOLD}" "${C_RESET}" "$*"; }
warn() { printf '  %s!%s  %s\n' "${C_YELLOW}${C_BOLD}" "${C_RESET}" "$*"; }
err()  { printf '  %s✗%s  %s\n' "${C_RED}${C_BOLD}" "${C_RESET}" "$*" >&2; }
die()  { err "$*"; exit 1; }

hr() {
  local ch="${1:-─}" i
  printf '  %s' "${C_DIM}"
  for ((i = 0; i < UI_WIDTH; i++)); do printf '%s' "$ch"; done
  printf '%s\n' "${C_RESET}"
}

step() {
  UI_STEP_CUR=$((UI_STEP_CUR + 1))
  local label="$*"
  local n="$UI_STEP_CUR" t="$UI_STEP_TOTAL"
  printf '\n'
  hr
  if [[ "$t" -gt 0 ]]; then
    printf '  %s●%s %s步骤 %s/%s%s  %s%s%s\n' \
      "${C_A5}${C_BOLD}" "${C_RESET}" \
      "${C_DIM}" "$n" "$t" "${C_RESET}" \
      "${C_BOLD}${C_WHITE}" "$label" "${C_RESET}"
  else
    printf '  %s●%s  %s%s%s\n' \
      "${C_A5}${C_BOLD}" "${C_RESET}" \
      "${C_BOLD}${C_WHITE}" "$label" "${C_RESET}"
  fi
  hr
}

print_banner() {
  local title="${1:-agent-status}"
  printf '\n'
  printf '  %s╭──────────────────────────────────────────────────────╮%s\n' "${C_A4}" "${C_RESET}"
  printf '  %s│%s                                                      %s│%s\n' "${C_A4}" "${C_RESET}" "${C_A4}" "${C_RESET}"
  printf '  %s│%s   %s █████╗  ███████╗%s                                %s│%s\n' "${C_A4}" "${C_RESET}" "${C_A1}" "${C_RESET}" "${C_A4}" "${C_RESET}"
  printf '  %s│%s   %s██╔══██╗ ██╔════╝%s                                %s│%s\n' "${C_A4}" "${C_RESET}" "${C_A2}" "${C_RESET}" "${C_A4}" "${C_RESET}"
  printf '  %s│%s   %s███████║ ███████╗%s  agent-status                  %s│%s\n' "${C_A4}" "${C_RESET}" "${C_A3}${C_BOLD}" "${C_RESET}" "${C_A4}" "${C_RESET}"
  printf '  %s│%s   %s██╔══██║ ╚════██║%s  会话监测 · 用量统计 · 安装器    %s│%s\n' "${C_A4}" "${C_RESET}" "${C_A4}" "${C_RESET}" "${C_A4}" "${C_RESET}"
  printf '  %s│%s   %s██║  ██║ ███████║%s                                %s│%s\n' "${C_A4}" "${C_RESET}" "${C_A5}" "${C_RESET}" "${C_A4}" "${C_RESET}"
  printf '  %s│%s   %s╚═╝  ╚═╝ ╚══════╝%s                                %s│%s\n' "${C_A4}" "${C_RESET}" "${C_MAGENTA}" "${C_RESET}" "${C_A4}" "${C_RESET}"
  printf '  %s│%s                                                      %s│%s\n' "${C_A4}" "${C_RESET}" "${C_A4}" "${C_RESET}"
  printf '  %s│%s   %s▸%s %-48s %s│%s\n' "${C_A4}" "${C_RESET}" "${C_GREEN}" "${C_RESET}" "$title" "${C_A4}" "${C_RESET}"
  printf '  %s╰──────────────────────────────────────────────────────╯%s\n' "${C_A4}" "${C_RESET}"
  printf '\n'
}

print_done() {
  local msg="${1:-完成}" dir="${2:-}"
  printf '\n'
  printf '  %s╭──────────────────────────────────────────────────────╮%s\n' "${C_GREEN}" "${C_RESET}"
  printf '  %s│%s  %s✦  %s%s%s\n' "${C_GREEN}" "${C_RESET}" "${C_GREEN}${C_BOLD}" "${C_RESET}${C_BOLD}" "$msg" "${C_RESET}"
  if [[ -n "$dir" ]]; then
    printf '  %s│%s  %s目录%s  %s\n' "${C_GREEN}" "${C_RESET}" "${C_DIM}" "${C_RESET}" "$dir"
  fi
  printf '  %s│%s  %s提示%s  agent-status status | update | restart\n' "${C_GREEN}" "${C_RESET}" "${C_DIM}" "${C_RESET}"
  printf '  %s╰──────────────────────────────────────────────────────╯%s\n\n' "${C_GREEN}" "${C_RESET}"
}

kv() {
  # kv "标签" "值"
  printf '  %s%-10s%s %s\n' "${C_DIM}" "$1" "${C_RESET}" "$2"
}

have_tty() { [[ -t 0 || -t 1 ]]; }

prompt() {
  local msg="$1" def="${2:-}" ans
  if [[ -n "$def" ]]; then
    printf '  %s?%s  %s %s[%s]%s: ' "${C_A2}${C_BOLD}" "${C_RESET}" "$msg" "${C_DIM}" "$def" "${C_RESET}" >&2
    read -r ans || true
    printf '%s' "${ans:-$def}"
  else
    printf '  %s?%s  %s: ' "${C_A2}${C_BOLD}" "${C_RESET}" "$msg" >&2
    read -r ans || true
    printf '%s' "$ans"
  fi
}

confirm() {
  local msg="$1"
  [[ "$YES" -eq 1 ]] && return 0
  have_tty || die "非交互模式请加 --yes"
  local ans
  printf '  %s?%s  %s %s[y/N]%s: ' "${C_YELLOW}${C_BOLD}" "${C_RESET}" "$msg" "${C_DIM}" "${C_RESET}" >&2
  read -r ans || true
  [[ "$ans" == "y" || "$ans" == "Y" || "$ans" == "yes" ]]
}

detect_arch() {
  local m
  m="$(uname -m)"
  case "$m" in
    x86_64|amd64) echo amd64 ;;
    aarch64|arm64) echo arm64 ;;
    *) die "不支持的 CPU 架构: $m" ;;
  esac
}

ensure_dirs() {
  mkdir -p "$BIN_DIR" "$CONFIG_DIR" "$DATA_DIR" "$LOG_DIR" "$STATE_DIR" "$SYSTEMD_USER_DIR" "$LOCAL_BIN"
}

random_key() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 24
  else
    head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n'
  fi
}

download() {
  local url="$1" dest="$2"
  if command -v curl >/dev/null 2>&1; then
    if [[ -t 1 ]]; then
      curl -fL --progress-bar "$url" -o "$dest"
    else
      curl -fsSL "$url" -o "$dest"
    fi
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$dest" "$url"
  else
    die "需要 curl 或 wget"
  fi
}

github_release_tag() {
  if [[ "$VERSION" != "latest" ]]; then
    echo "$VERSION"
    return
  fi
  local json tag auth_hdr
  auth_hdr=()
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    auth_hdr=(-H "Authorization: Bearer $GITHUB_TOKEN")
  elif [[ -n "${GH_TOKEN:-}" ]]; then
    auth_hdr=(-H "Authorization: Bearer $GH_TOKEN")
  fi
  json="$(curl -fsSL "${auth_hdr[@]}" "${RELEASE_API}/latest" 2>/dev/null || true)"
  tag="$(printf '%s' "$json" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  if [[ -z "$tag" ]]; then
    if printf '%s' "$json" | grep -q 'rate limit'; then
      die "GitHub API 限流。请用 --version v0.1.1 指定版本，或设置 GITHUB_TOKEN 环境变量。"
    fi
    die "无法获取 $REPO 的最新 Release（请确认仓库已公开且已发版）"
  fi
  echo "$tag"
}

asset_url() {
  local tag="$1" name="$2"
  echo "https://github.com/${REPO}/releases/download/${tag}/${name}"
}

install_binary_from_release() {
  local role="$1" arch tag name tmp dest
  arch="$(detect_arch)"
  tag="$(github_release_tag)"
  if [[ "$role" == "server" ]]; then
    name="agent-status-server-linux-${arch}"
    dest="$BIN_DIR/agent-status-server"
  else
    name="agent-status-monitor-linux-${arch}"
    dest="$BIN_DIR/agent-status-monitor"
  fi
  tmp="$(mktemp)"
  info "下载 $name（$tag）"
  if ! download "$(asset_url "$tag" "$name")" "$tmp"; then
    rm -f "$tmp"
    die "下载失败: $name"
  fi
  if [[ -f "$dest" ]]; then
    cp -f "$dest" "${dest}.bak"
  fi
  install -m 755 "$tmp" "$dest"
  rm -f "$tmp"
  ok "已安装 $dest"
}

install_binary_local() {
  local role="$1" src dest
  if [[ "$role" == "server" ]]; then
    src="$LOCAL_BIN_SRC/agent-status-server"
    [[ -f "$src" ]] || src="$LOCAL_BIN_SRC/agent-status-server-linux-$(detect_arch)"
    dest="$BIN_DIR/agent-status-server"
  else
    src="$LOCAL_BIN_SRC/agent-status-monitor"
    [[ -f "$src" ]] || src="$LOCAL_BIN_SRC/agent-status-monitor-linux-$(detect_arch)"
    dest="$BIN_DIR/agent-status-monitor"
  fi
  [[ -f "$src" ]] || die "本地二进制不存在: $src"
  if [[ -f "$dest" ]]; then
    cp -f "$dest" "${dest}.bak"
  fi
  install -m 755 "$src" "$dest"
  log "已安装 $dest（本地文件）"
}

install_binary() {
  local role="$1"
  if [[ -n "$LOCAL_BIN_SRC" ]]; then
    install_binary_local "$role"
  else
    install_binary_from_release "$role"
  fi
}

write_server_env() {
  local path="$CONFIG_DIR/server.env" key="$1" addr="$2"
  if [[ -f "$path" && "$FORCE_CONFIG" -eq 0 ]]; then
    info "保留已有配置 $path"
    return
  fi
  if [[ -f "$path" ]]; then
    cp -f "$path" "$path.bak-$(date +%Y%m%d%H%M%S)"
  fi
  cat >"$path" <<EOF
AGENT_STATUS_ADDR=${addr}
AGENT_STATUS_KEY=${key}
AGENT_STATUS_DB=${DATA_DIR}/agent-status.db
EOF
  chmod 600 "$path"
  ok "已写入 $path"
}

write_monitor_json() {
  local path="$CONFIG_DIR/monitor.json"
  local server_url="$1" key="$2"
  local machine_id machine_name platform
  machine_id="$(hostname 2>/dev/null || echo linux-host)"
  machine_name="$machine_id"
  platform="linux"
  if [[ -f "$path" && "$FORCE_CONFIG" -eq 0 ]]; then
    info "保留已有配置 $path"
    return
  fi
  if [[ -f "$path" ]]; then
    cp -f "$path" "$path.bak-$(date +%Y%m%d%H%M%S)"
  fi
  cat >"$path" <<EOF
{
  "server_url": "${server_url}",
  "key": "${key}",
  "machine_id": "${machine_id}",
  "machine_name": "${machine_name}",
  "platform": "${platform}",
  "report_interval_sec": 60,
  "codex_file_watch": true,
  "codex_sessions_dir": "",
  "state_file": ""
}
EOF
  chmod 600 "$path"
  ok "已写入 $path"
}

write_systemd_server() {
  local unit="$SYSTEMD_USER_DIR/agent-status-server.service"
  cat >"$unit" <<EOF
[Unit]
Description=agent-status 服务端
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=${CONFIG_DIR}/server.env
ExecStart=${BIN_DIR}/agent-status-server
WorkingDirectory=${INSTALL_ROOT}
Restart=on-failure
RestartSec=5
StandardOutput=append:${LOG_DIR}/server.log
StandardError=append:${LOG_DIR}/server.log

[Install]
WantedBy=default.target
EOF
  ok "已写入 $unit"
}

write_systemd_monitor() {
  local unit="$SYSTEMD_USER_DIR/agent-status-monitor.service"
  cat >"$unit" <<EOF
[Unit]
Description=agent-status 监测端
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${BIN_DIR}/agent-status-monitor -config ${CONFIG_DIR}/monitor.json
WorkingDirectory=${INSTALL_ROOT}
Restart=on-failure
RestartSec=5
StandardOutput=append:${LOG_DIR}/monitor.log
StandardError=append:${LOG_DIR}/monitor.log

[Install]
WantedBy=default.target
EOF
  ok "已写入 $unit"
}

systemd_reload() {
  systemctl --user daemon-reload 2>/dev/null || true
}

unit_for_role() {
  case "$1" in
    server) echo agent-status-server.service ;;
    monitor) echo agent-status-monitor.service ;;
    *) die "无效角色: $1" ;;
  esac
}

roles_expand() {
  local r="${1:-}"
  if [[ -z "$r" || "$r" == "all" ]]; then
    local out=()
    [[ -x "$BIN_DIR/agent-status-server" || -f "$SYSTEMD_USER_DIR/agent-status-server.service" ]] && out+=(server)
    [[ -x "$BIN_DIR/agent-status-monitor" || -f "$SYSTEMD_USER_DIR/agent-status-monitor.service" ]] && out+=(monitor)
    if [[ ${#out[@]} -eq 0 ]]; then
      die "尚未安装，请指定 --role server|monitor"
    fi
    printf '%s\n' "${out[@]}"
  else
    echo "$r"
  fi
}

svc() {
  local action="$1" role="$2" unit
  unit="$(unit_for_role "$role")"
  case "$action" in
    start|stop|restart|enable|disable)
      systemctl --user "$action" "$unit"
      ;;
    status)
      systemctl --user --no-pager --full status "$unit" || true
      ;;
    is-active)
      systemctl --user is-active "$unit" 2>/dev/null || echo inactive
      ;;
  esac
}

persist_self() {
  # curl|bash runs from a pipe; keep a durable manager copy under install root
  local dest="$INSTALL_ROOT/install.sh" self="${BASH_SOURCE[0]:-}"
  if [[ -n "$self" && -f "$self" && -r "$self" ]]; then
    cp -f "$self" "$dest"
  elif [[ -n "${INSTALLER_SOURCE_URL:-}" ]]; then
    download "$INSTALLER_SOURCE_URL" "$dest" || return 0
  else
    # last resort: re-fetch from repo main
    download "${RAW_BASE}/main/scripts/install.sh" "$dest" || return 0
  fi
  chmod 755 "$dest" 2>/dev/null || true
  ok "管理脚本: $dest"
}

link_shim() {
  local self="$INSTALL_ROOT/install.sh" dest="$LOCAL_BIN/agent-status"
  [[ -f "$self" ]] || return 0
  mkdir -p "$LOCAL_BIN" 2>/dev/null || true
  ln -sfn "$self" "$dest" 2>/dev/null || cp -f "$self" "$dest" 2>/dev/null || true
  if [[ -e "$dest" ]]; then
    chmod +x "$dest" 2>/dev/null || true
    ok "命令入口: $dest"
  fi
}

detect_claude() {
  command -v claude >/dev/null 2>&1 && return 0
  [[ -d "$HOME/.claude" ]] && return 0
  return 1
}

detect_codex() {
  command -v codex >/dev/null 2>&1 && return 0
  [[ -d "$HOME/.codex" ]] && return 0
  return 1
}

init_agents() {
  local mon="$BIN_DIR/agent-status-monitor"
  local cfg="$CONFIG_DIR/monitor.json"
  [[ -x "$mon" ]] || die "监测端二进制不存在，请先 install --role monitor"
  [[ -f "$cfg" ]] || die "监测端配置不存在: $cfg"

  log "Agent 探测："
  if detect_claude; then
    log "  Claude Code：已发现"
  else
    log "  Claude Code：未发现"
  fi
  if detect_codex; then
    log "  Codex：已发现"
  else
    log "  Codex：未发现"
  fi

  if detect_claude; then
    log "正在初始化 Claude Code hooks..."
    "$mon" --init --claude --config "$cfg"
  else
    log "跳过 Claude hooks（未检测到 Claude）"
  fi
}

cmd_status() {
  local r unit active
  printf '\n'
  printf '  %s╭──────────────────────────────────────────────────────╮%s\n' "${C_A3}" "${C_RESET}"
  printf '  %s│%s  %s系统状态%s                                           %s│%s\n' "${C_A3}" "${C_RESET}" "${C_BOLD}" "${C_RESET}" "${C_A3}" "${C_RESET}"
  printf '  %s╰──────────────────────────────────────────────────────╯%s\n' "${C_A3}" "${C_RESET}"

  while IFS= read -r r; do
    printf '\n'
    printf '  %s◆ %s%s%s\n' "${C_A5}${C_BOLD}" "${C_RESET}${C_BOLD}" "$r" "${C_RESET}"
    hr "·"

    if [[ -x "$BIN_DIR/agent-status-$r" ]]; then
      kv "二进制" "$BIN_DIR/agent-status-$r"
      if [[ "$r" == "monitor" ]]; then
        local ver
        ver="$("$BIN_DIR/agent-status-monitor" -version 2>/dev/null || true)"
        [[ -n "$ver" ]] && kv "版本" "$ver"
      fi
    else
      kv "二进制" "缺失"
    fi

    case "$r" in
      server)
        if [[ -f "$CONFIG_DIR/server.env" ]]; then
          local line k v
          while IFS= read -r line || [[ -n "$line" ]]; do
            [[ -z "$line" || "$line" == \#* ]] && continue
            k="${line%%=*}"; v="${line#*=}"
            case "$k" in
              AGENT_STATUS_KEY) kv "KEY" "****" ;;
              AGENT_STATUS_ADDR) kv "ADDR" "$v" ;;
              AGENT_STATUS_DB) kv "DB" "$v" ;;
              *) kv "$k" "$v" ;;
            esac
          done < "$CONFIG_DIR/server.env"
        fi
        ;;
      monitor)
        if [[ -f "$CONFIG_DIR/monitor.json" ]] && command -v python3 >/dev/null 2>&1; then
          local url machine platform
          url="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("server_url",""))' "$CONFIG_DIR/monitor.json" 2>/dev/null || true)"
          machine="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("machine_name") or d.get("machine_id",""))' "$CONFIG_DIR/monitor.json" 2>/dev/null || true)"
          platform="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("platform",""))' "$CONFIG_DIR/monitor.json" 2>/dev/null || true)"
          [[ -n "$url" ]] && kv "URL" "$url"
          [[ -n "$machine" ]] && kv "机器" "$machine"
          [[ -n "$platform" ]] && kv "平台" "$platform"
          kv "KEY" "****"
        fi
        ;;
    esac

    unit="$(unit_for_role "$r")"
    active="$(systemctl --user is-active "$unit" 2>/dev/null || echo inactive)"
    if [[ "$active" == "active" ]]; then
      printf '  %s%-10s%s %s● active%s  %s\n' "${C_DIM}" "服务" "${C_RESET}" "${C_GREEN}${C_BOLD}" "${C_RESET}" "$unit"
    else
      printf '  %s%-10s%s %s○ %s%s  %s\n' "${C_DIM}" "服务" "${C_RESET}" "${C_YELLOW}" "$active" "${C_RESET}" "$unit"
    fi
  done < <(roles_expand "$ROLE")
  printf '\n'
}

cmd_control() {
  local action="$1" r
  while IFS= read -r r; do
    log "执行 $action → $r"
    svc "$action" "$r"
  done < <(roles_expand "$ROLE")
}

cmd_config_get() {
  local r
  ROLE="${ROLE:-all}"
  while IFS= read -r r; do
    case "$r" in
      server)
        [[ -f "$CONFIG_DIR/server.env" ]] || { log "服务端配置不存在"; continue; }
        sed -E 's/^(AGENT_STATUS_KEY=).*/\1****/' "$CONFIG_DIR/server.env"
        ;;
      monitor)
        [[ -f "$CONFIG_DIR/monitor.json" ]] || { log "监测端配置不存在"; continue; }
        if command -v python3 >/dev/null 2>&1; then
          python3 - "$CONFIG_DIR/monitor.json" <<'PY'
import json,sys
p=sys.argv[1]
with open(p) as f: d=json.load(f)
if "key" in d: d["key"]="****"
print(json.dumps(d, ensure_ascii=False, indent=2))
PY
        else
          cat "$CONFIG_DIR/monitor.json"
        fi
        ;;
    esac
  done < <(roles_expand "$ROLE")
}

cmd_config_set() {
  local r key val
  [[ ${#CONFIG_KV[@]} -ge 1 ]] || die "config set 需要 KEY=VALUE"
  ROLE="${ROLE:-}"
  [[ -n "$ROLE" && "$ROLE" != "all" ]] || die "config set 需要 --role server|monitor"
  r="$ROLE"
  for pair in "${CONFIG_KV[@]}"; do
    key="${pair%%=*}"
    val="${pair#*=}"
    [[ "$key" != "$pair" ]] || die "参数格式错误: $pair（应为 KEY=VALUE）"
    case "$r" in
      server)
        local envf="$CONFIG_DIR/server.env"
        [[ -f "$envf" ]] || die "缺少文件 $envf"
        cp -f "$envf" "$envf.bak-$(date +%Y%m%d%H%M%S)"
        case "$key" in
          key|AGENT_STATUS_KEY) key=AGENT_STATUS_KEY ;;
          addr|AGENT_STATUS_ADDR) key=AGENT_STATUS_ADDR ;;
          db|AGENT_STATUS_DB) key=AGENT_STATUS_DB ;;
        esac
        if grep -q "^${key}=" "$envf"; then
          sed -i "s|^${key}=.*|${key}=${val}|" "$envf"
        else
          echo "${key}=${val}" >>"$envf"
        fi
        log "已更新 $envf 的 $key"
        ;;
      monitor)
        local mf="$CONFIG_DIR/monitor.json"
        [[ -f "$mf" ]] || die "缺少文件 $mf"
        cp -f "$mf" "$mf.bak-$(date +%Y%m%d%H%M%S)"
        case "$key" in
          server-url|server_url) key=server_url ;;
          machine-id|machine_id) key=machine_id ;;
          machine-name|machine_name) key=machine_name ;;
        esac
        python3 - "$mf" "$key" "$val" <<'PY'
import json, sys
path, k, v = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, encoding="utf-8") as f:
    d = json.load(f)
if v.lower() in ("true", "false"):
    d[k] = v.lower() == "true"
elif v.isdigit():
    d[k] = int(v)
else:
    d[k] = v
with open(path, "w", encoding="utf-8") as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
    f.write("\n")
print("updated", path, k)
PY
        ;;
    esac
  done
}

cmd_uninstall() {
  local r
  ROLE="${ROLE:-all}"
  while IFS= read -r r; do
    systemctl --user disable --now "$(unit_for_role "$r")" 2>/dev/null || true
    rm -f "$SYSTEMD_USER_DIR/$(unit_for_role "$r")"
    log "已移除服务单元: $r"
  done < <(roles_expand "$ROLE")
  systemd_reload
  if [[ "$PURGE" -eq 1 ]]; then
    rm -rf "$INSTALL_ROOT"
    log "已删除安装目录 $INSTALL_ROOT"
  else
    log "已保留 $INSTALL_ROOT（加 --purge 可删除）"
  fi
}

cmd_update() {
  print_banner "更新二进制"
  local r
  ROLE="${ROLE:-all}"
  local roles=()
  while IFS= read -r r; do roles+=("$r"); done < <(roles_expand "$ROLE")
  UI_STEP_CUR=0
  UI_STEP_TOTAL=${#roles[@]}
  for r in "${roles[@]}"; do
    step "更新 $r"
    systemctl --user stop "$(unit_for_role "$r")" 2>/dev/null || true
    install_binary "$r"
    systemctl --user start "$(unit_for_role "$r")" 2>/dev/null || true
    ok "已更新 $r"
  done
  print_done "更新完成" "$INSTALL_ROOT"
  cmd_status
}

interactive_fill() {
  local want_server=0 want_monitor=0
  local keep_server=0 keep_monitor=0
  local existing_url="" existing_key="" default_url="http://127.0.0.1:29125"

  if [[ -z "$ROLE" ]]; then
    have_tty || die "非交互安装请指定 --role 与 --yes"
    printf '  %s选择要安装的角色%s
' "${C_BOLD}" "${C_RESET}"
    printf '  %s┌────────────────────────────────────────────────────┐%s
' "${C_DIM}" "${C_RESET}"
    printf '  %s│%s  %s1%s  服务端 server     接收上报、WebSocket、API      %s│%s
' "${C_DIM}" "${C_RESET}" "${C_A1}${C_BOLD}" "${C_RESET}" "${C_DIM}" "${C_RESET}"
    printf '  %s│%s  %s2%s  监测端 monitor    扫描会话 / 用量并上报         %s│%s
' "${C_DIM}" "${C_RESET}" "${C_A2}${C_BOLD}" "${C_RESET}" "${C_DIM}" "${C_RESET}"
    printf '  %s│%s  %s3%s  两者都装 all      本机完整部署                  %s│%s
' "${C_DIM}" "${C_RESET}" "${C_A5}${C_BOLD}" "${C_RESET}" "${C_DIM}" "${C_RESET}"
    printf '  %s└────────────────────────────────────────────────────┘%s
' "${C_DIM}" "${C_RESET}"
    local c
    c="$(prompt "请输入序号" "2")"
    case "$c" in
      1) ROLE=server ;;
      2) ROLE=monitor ;;
      3) ROLE=all ;;
      *) die "无效选项" ;;
    esac
  fi
  case "$ROLE" in
    server) want_server=1 ;;
    monitor) want_monitor=1 ;;
    all) want_server=1; want_monitor=1 ;;
    *) die "--role 只能是 server|monitor|all" ;;
  esac

  if [[ -f "$CONFIG_DIR/server.env" ]]; then
    existing_key="$(sed -n 's/^AGENT_STATUS_KEY=//p' "$CONFIG_DIR/server.env" | head -n1)"
    [[ "$FORCE_CONFIG" -eq 0 ]] && keep_server=1
  fi
  if [[ -f "$CONFIG_DIR/monitor.json" ]]; then
    if command -v python3 >/dev/null 2>&1; then
      existing_url="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("server_url",""))' "$CONFIG_DIR/monitor.json" 2>/dev/null || true)"
      if [[ -z "$existing_key" ]]; then
        existing_key="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("key",""))' "$CONFIG_DIR/monitor.json" 2>/dev/null || true)"
      fi
    fi
    [[ "$FORCE_CONFIG" -eq 0 ]] && keep_monitor=1
  fi
  [[ -n "$existing_url" ]] && default_url="$existing_url"

  if [[ "$want_server" -eq 1 ]]; then
    if [[ "$keep_server" -eq 1 ]]; then
      ok "复用已有服务端配置"
      [[ -n "$KEY" ]] || KEY="$existing_key"
    else
      if [[ -z "$KEY" ]]; then
        if have_tty && [[ "$YES" -eq 0 ]]; then
          if [[ -n "$existing_key" ]]; then
            KEY="$(prompt "服务端密钥（留空沿用已有）" "$existing_key")"
          else
            KEY="$(prompt "服务端密钥（留空则自动生成）" "")"
          fi
        elif [[ -n "$existing_key" ]]; then
          KEY="$existing_key"
        fi
        [[ -n "$KEY" ]] || KEY="$(random_key)"
      fi
      if have_tty && [[ "$YES" -eq 0 ]]; then
        ADDR="$(prompt "监听地址" "$ADDR")"
      fi
    fi
  fi

  if [[ "$want_monitor" -eq 1 ]]; then
    if [[ "$keep_monitor" -eq 1 ]]; then
      ok "复用已有监测端配置（${default_url}）"
      [[ -n "$SERVER_URL" ]] || SERVER_URL="$default_url"
      if [[ -z "$KEY" ]]; then
        KEY="$existing_key"
      fi
    else
      if [[ -z "$SERVER_URL" ]]; then
        if have_tty && [[ "$YES" -eq 0 ]]; then
          SERVER_URL="$(prompt "服务端地址" "$default_url")"
        else
          SERVER_URL="$default_url"
        fi
      fi
      if [[ -z "$KEY" ]]; then
        if have_tty && [[ "$YES" -eq 0 ]]; then
          if [[ -n "$existing_key" ]]; then
            KEY="$(prompt "共享密钥（留空沿用已有）" "$existing_key")"
          else
            KEY="$(prompt "共享密钥" "")"
          fi
        else
          KEY="$existing_key"
        fi
      fi
      [[ -n "$KEY" ]] || die "安装监测端需要 --key"
    fi
  fi
}

cmd_install() {
  print_banner "安装向导"
  ensure_dirs
  interactive_fill

  local want_server=0 want_monitor=0
  case "$ROLE" in
    server) want_server=1 ;;
    monitor) want_monitor=1 ;;
    all) want_server=1; want_monitor=1 ;;
  esac

  UI_STEP_CUR=0
  UI_STEP_TOTAL=1
  [[ "$want_server" -eq 1 ]] && UI_STEP_TOTAL=$((UI_STEP_TOTAL + 1))
  [[ "$want_monitor" -eq 1 ]] && UI_STEP_TOTAL=$((UI_STEP_TOTAL + 1))
  [[ "$want_monitor" -eq 1 && "$NO_INIT_AGENTS" -eq 0 ]] && UI_STEP_TOTAL=$((UI_STEP_TOTAL + 1))

  if [[ "$want_server" -eq 1 ]]; then
    step "安装服务端"
    install_binary server
    write_server_env "$KEY" "$ADDR"
    write_systemd_server
    ok "服务端就绪"
  fi
  if [[ "$want_monitor" -eq 1 ]]; then
    step "安装监测端"
    install_binary monitor
    write_monitor_json "$SERVER_URL" "$KEY"
    write_systemd_monitor
    ok "监测端就绪"
  fi

  step "启用并启动"
  systemd_reload
  persist_self
  link_shim

  if [[ "$NO_ENABLE" -eq 0 ]]; then
    [[ "$want_server" -eq 1 ]] && systemctl --user enable --now agent-status-server.service
    [[ "$want_monitor" -eq 1 ]] && systemctl --user enable --now agent-status-monitor.service
  else
    [[ "$want_server" -eq 1 ]] && systemctl --user restart agent-status-server.service 2>/dev/null || systemctl --user start agent-status-server.service || true
    [[ "$want_monitor" -eq 1 ]] && systemctl --user restart agent-status-monitor.service 2>/dev/null || systemctl --user start agent-status-monitor.service || true
  fi
  ok "服务已启动"

  if [[ "$want_monitor" -eq 1 && "$NO_INIT_AGENTS" -eq 0 ]]; then
    step "初始化 Agent"
    init_agents || true
  fi

  print_done "安装完成" "$INSTALL_ROOT"
  cmd_status
}

parse_args() {
  if [[ $# -eq 0 ]]; then
    CMD="install"
    return
  fi
  case "$1" in
    install|update|status|start|stop|restart|enable|disable|config|init-agents|uninstall)
      CMD="$1"; shift
      ;;
    -h|--help)
      usage; exit 0
      ;;
    --*)
      CMD="install"
      ;;
    *)
      # allow bare flags after default install
      CMD="install"
      ;;
  esac

  if [[ "$CMD" == "config" ]]; then
    CONFIG_ACTION="${1:-get}"
    shift || true
    if [[ "$CONFIG_ACTION" != "get" && "$CONFIG_ACTION" != "set" ]]; then
      die "config 子命令只能是 get|set"
    fi
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --role) ROLE="${2:-}"; shift 2 ;;
      --yes|-y) YES=1; shift ;;
      --version) VERSION="${2:-}"; shift 2 ;;
      --server-url) SERVER_URL="${2:-}"; shift 2 ;;
      --key) KEY="${2:-}"; shift 2 ;;
      --addr) ADDR="${2:-}"; shift 2 ;;
      --no-init-agents) NO_INIT_AGENTS=1; shift ;;
      --no-enable) NO_ENABLE=1; shift ;;
      --local-bin) LOCAL_BIN_SRC="${2:-}"; shift 2 ;;
      --force-config) FORCE_CONFIG=1; shift ;;
      --purge) PURGE=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *=*)
        if [[ "$CMD" == "config" && "$CONFIG_ACTION" == "set" ]]; then
          CONFIG_KV+=("$1"); shift
        else
          die "未知参数: $1"
        fi
        ;;
      *)
        die "未知参数: $1"
        ;;
    esac
  done
}

main() {
  parse_args "$@"
  case "$CMD" in
    install) cmd_install ;;
    update)  cmd_update ;;
    status) cmd_status ;;
    start|stop|restart|enable|disable) cmd_control "$CMD" ;;
    config)
      if [[ "$CONFIG_ACTION" == "set" ]]; then cmd_config_set; else cmd_config_get; fi
      ;;
    init-agents) init_agents ;;
    uninstall) cmd_uninstall ;;
    *) usage; exit 2 ;;
  esac
}

main "$@"
