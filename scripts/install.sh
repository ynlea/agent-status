#!/usr/bin/env bash
# agent-status 安装与本机管理（Linux）
# 交互：curl -fsSL .../install.sh | bash
# 非交互示例：
#   ./install.sh install --role server --key KEY --yes
#   ./install.sh install --role monitor --server-url URL --key KEY --yes
#   ./install.sh status|start|stop|restart --role all
#   ./install.sh uninstall --purge -y
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
FORCE_UPDATE=0
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
  uninstall           卸载服务；加 --purge 清理全部相关文件

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
  --purge             彻底清理：安装目录、命令入口、用量游标、Claude hooks
  --force             更新时即使版本相同也强制重装
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
  printf '
'
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
  local W=52
  printf '
'
  box_top "$C_A4" "$W"
  box_blank "$C_A4" "$W"
  # logo 行：左 AS 字标 + 右侧说明，全部按显示宽度对齐
  box_row "$C_A4" "  █████╗  ███████╗" "$W"
  box_row "$C_A4" " ██╔══██╗ ██╔════╝" "$W"
  box_row "$C_A4" " ███████║ ███████╗   agent-status" "$W"
  box_row "$C_A4" " ██╔══██║ ╚════██║   会话监测 · 用量统计 · 安装器" "$W"
  box_row "$C_A4" " ██║  ██║ ███████║" "$W"
  box_row "$C_A4" " ╚═╝  ╚═╝ ╚══════╝" "$W"
  box_blank "$C_A4" "$W"
  box_row "$C_A4" "  ▸ ${title}" "$W"
  box_bot "$C_A4" "$W"
  printf '
'
}

print_done() {
  local msg="${1:-完成}" dir="${2:-}"
  local W=52
  printf '
'
  box_top "$C_GREEN" "$W"
  box_row "$C_GREEN" "  ✦  ${msg}" "$W"
  if [[ -n "$dir" ]]; then
    box_row "$C_GREEN" "  目录  $(pretty_path "$dir")" "$W"
  fi
  box_row "$C_GREEN" "  提示  agent-status status | update | restart" "$W"
  box_bot "$C_GREEN" "$W"
  printf '
'
}

kv() {
  # kv "标签" "值"
  printf '  %s%-10s%s %s
' "${C_DIM}" "$1" "${C_RESET}" "$2"
}

# 家目录折叠为 ~
pretty_path() {
  local p="$1"
  if [[ -n "${HOME:-}" && "$p" == "$HOME"* ]]; then
    printf '~%s' "${p#"$HOME"}"
  else
    printf '%s' "$p"
  fi
}

path_line() {
  # path_line "标签" "绝对路径"
  printf '  %s%-10s%s %s%s%s
' "${C_DIM}" "$1" "${C_RESET}" "${C_A2}" "$(pretty_path "$2")" "${C_RESET}"
}

human_size() {
  local b="$1"
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec --suffix=B "$b" 2>/dev/null && return
  fi
  awk -v b="$b" 'BEGIN{
    s="B KMGTPE";
    while (b>=1024 && length(s)>1) { b/=1024; s=substr(s,2) }
    printf (b<10?"%.1f":"%.0f") "%sB
", b, substr(s,1,1)
  }'
}

draw_bar() {
  # draw_bar current total [label]
  local cur="${1:-0}" total="${2:-0}" label="${3:-}"
  local pct=0 w=36 filled empty i
  if [[ "$total" -gt 0 ]]; then
    pct=$(( cur * 100 / total ))
    (( pct > 100 )) && pct=100
  fi
  filled=$(( pct * w / 100 ))
  empty=$(( w - filled ))
  printf '\r  %s' "${C_A2}"
  printf '['
  for ((i=0; i<filled; i++)); do printf '█'; done
  for ((i=0; i<empty; i++)); do printf '░'; done
  printf ']%s %s%3d%%%s' "${C_RESET}" "${C_BOLD}" "$pct" "${C_RESET}"
  if [[ "$total" -gt 0 ]]; then
    printf '  %s%s%s / %s%s%s'       "${C_DIM}" "$(human_size "$cur")" "${C_RESET}"       "${C_DIM}" "$(human_size "$total")" "${C_RESET}"
  fi
  if [[ -n "$label" ]]; then
    printf '  %s%s%s' "${C_DIM}" "$label" "${C_RESET}"
  fi
  printf '   '
}



# 显示宽度（中文等宽字符计 2），并渲染对齐边框
vis_width() {
  # usage: vis_width "文本"
  local s="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys,re,unicodedata
s=sys.argv[1]
s=re.sub(r"\x1b\[[0-9;]*m","",s)
w=0
for ch in s:
    w += 2 if unicodedata.east_asian_width(ch) in ("F","W") else 1
print(w)' "$s" 2>/dev/null && return
  fi
  printf '%s' "${#s}"
}

pad_vis() {
  # pad_vis "文本" 目标显示宽度 → stdout
  local s="$1" target="$2" w pad
  w="$(vis_width "$s")"
  pad=$((target - w))
  (( pad < 0 )) && pad=0
  printf '%s%*s' "$s" "$pad" ''
}

# 画一行：  左框 + 内文(已按宽度补齐) + 右框
# box_row COLOR "纯文本内容" [INNER_WIDTH=52]
box_row() {
  local color="${1:-$C_A4}" content="${2:-}" width="${3:-52}"
  printf '  %s│%s %s%s│%s\n' "$color" "${C_RESET}" "$(pad_vis "$content" "$width")" "$color" "${C_RESET}"
}

box_top() {
  local color="${1:-$C_A4}" width="${2:-52}" i
  printf '  %s╭' "$color"
  for ((i=0; i<width+2; i++)); do printf '─'; done
  printf '╮%s\n' "${C_RESET}"
}

box_bot() {
  local color="${1:-$C_A4}" width="${2:-52}" i
  printf '  %s╰' "$color"
  for ((i=0; i<width+2; i++)); do printf '─'; done
  printf '╯%s\n' "${C_RESET}"
}

box_blank() {
  box_row "${1:-$C_A4}" "" "${2:-52}"
}

box_title_row() {
  # 左边标题条：─ Title ────────
  local color="${1:-$C_A5}" title="$2" width="${3:-52}"
  local plain="─ ${title} "
  local w pad i
  w="$(vis_width "$plain")"
  pad=$((width + 2 - w))
  (( pad < 0 )) && pad=0
  printf '  %s╭%s' "$color" "$plain"
  for ((i=0; i<pad; i++)); do printf '─'; done
  printf '╮%s\n' "${C_RESET}"
}

# 是否可交互输入：stdout 在终端，且能从 stdin 或 /dev/tty 读
# 注意：curl|bash 时 stdin 是管道，不能只靠 -t 1，否则会立刻用默认值“自动装监测端”
have_tty() { [[ -t 1 ]] && { [[ -t 0 ]] || [[ -r /dev/tty ]]; }; }

# 从真实终端读一行（兼容 curl|bash / process substitution）
read_tty() {
  # usage: read_tty varname
  local __var="$1"
  local __line=""
  if [[ -t 0 ]]; then
    IFS= read -r __line || true
  elif [[ -r /dev/tty ]]; then
    IFS= read -r __line < /dev/tty || true
  else
    __line=""
  fi
  printf -v "$__var" '%s' "$__line"
}

prompt() {
  local msg="$1" def="${2:-}" ans
  if [[ -n "$def" ]]; then
    printf '  %s?%s  %s %s[%s]%s: ' "${C_A2}${C_BOLD}" "${C_RESET}" "$msg" "${C_DIM}" "$def" "${C_RESET}" >&2
    read_tty ans
    printf '%s' "${ans:-$def}"
  else
    printf '  %s?%s  %s: ' "${C_A2}${C_BOLD}" "${C_RESET}" "$msg" >&2
    read_tty ans
    printf '%s' "$ans"
  fi
}

confirm() {
  local msg="$1"
  [[ "$YES" -eq 1 ]] && return 0
  have_tty || die "非交互模式请加 --yes"
  local ans
  printf '  %s?%s  %s %s[y/N]%s: ' "${C_YELLOW}${C_BOLD}" "${C_RESET}" "$msg" "${C_DIM}" "${C_RESET}" >&2
  read_tty ans
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
  local total=0 cur=0 pid err=0

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    die "需要 curl 或 wget"
  fi

  path_line "目标" "$dest"
  printf '  %s%-10s%s %s\n' "${C_DIM}" "来源" "${C_RESET}" "$url"

  if command -v curl >/dev/null 2>&1; then
    # 尝试拿 Content-Length 画自定义进度条
    if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
      total="$(curl -fsSIL "$url" 2>/dev/null | awk 'tolower($1)=="content-length:"{print $2}' | tr -d '\r' | tail -n1)"
      total="${total:-0}"
      if [[ "$total" =~ ^[0-9]+$ ]] && [[ "$total" -gt 0 ]]; then
        curl -fL --silent --show-error "$url" -o "$dest" &
        pid=$!
        while kill -0 "$pid" 2>/dev/null; do
          if [[ -f "$dest" ]]; then
            cur="$(wc -c <"$dest" 2>/dev/null | tr -d ' ' || echo 0)"
          else
            cur=0
          fi
          draw_bar "$cur" "$total"
          sleep 0.12
        done
        wait "$pid" || err=$?
        if [[ -f "$dest" ]]; then
          cur="$(wc -c <"$dest" 2>/dev/null | tr -d ' ' || echo 0)"
        fi
        draw_bar "$cur" "$total"
        printf '
'
        [[ "$err" -eq 0 ]] || return "$err"
        ok "下载完成  $(human_size "$cur")"
        return 0
      fi
      # 未知大小：用 curl 自带进度条并缩进
      printf '  %s' "${C_A2}"
      curl -fL --progress-bar "$url" -o "$dest"
      local rc=$?
      printf '%s' "${C_RESET}"
      [[ $rc -eq 0 ]] || return $rc
      if [[ -f "$dest" ]]; then
        ok "下载完成  $(human_size "$(wc -c <"$dest" | tr -d ' ')")"
      else
        ok "下载完成"
      fi
      return 0
    fi
    curl -fsSL "$url" -o "$dest"
    return $?
  fi

  wget -qO "$dest" "$url"
}

normalize_version() {
  # v0.1.2 / 0.1.2 / dev → 可比对字符串
  local v
  v="$(printf '%s' "$1" | tr -d '[:space:]')"
  v="${v#v}"
  v="${v#V}"
  printf '%s' "$v"
}

local_binary_version() {
  # local_binary_version server|monitor → 版本或空
  local role="$1" bin
  bin="$BIN_DIR/agent-status-$role"
  [[ -x "$bin" ]] || { printf ''; return 0; }
  local out
  out="$("$bin" -version 2>/dev/null | head -n1 | tr -d '\r')" || out=""
  # 过滤非版本噪音
  if [[ -z "$out" || "$out" == *"flag"* || "$out" == *"Usage"* ]]; then
    printf ''
    return 0
  fi
  printf '%s' "$out"
}

should_skip_update() {
  # should_skip_update role target_tag → 0=跳过 1=需要更新
  local role="$1" target="$2" local_ver local_n target_n
  if [[ "$FORCE_UPDATE" -eq 1 ]]; then
    return 1
  fi
  local_ver="$(local_binary_version "$role")"
  if [[ -z "$local_ver" || "$local_ver" == "dev" ]]; then
    return 1
  fi
  local_n="$(normalize_version "$local_ver")"
  target_n="$(normalize_version "$target")"
  if [[ -n "$local_n" && -n "$target_n" && "$local_n" == "$target_n" ]]; then
    return 0
  fi
  return 1
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
  printf '  %s%-10s%s %s  %s(%s)%s
' "${C_DIM}" "资源" "${C_RESET}" "$name" "${C_A5}" "$tag" "${C_RESET}"
  if ! download "$(asset_url "$tag" "$name")" "$tmp"; then
    rm -f "$tmp"
    die "下载失败: $name"
  fi
  if [[ -f "$dest" ]]; then
    cp -f "$dest" "${dest}.bak"
    info "已备份 $(pretty_path "$dest").bak"
  fi
  install -m 755 "$tmp" "$dest"
  rm -f "$tmp"
  path_line "安装到" "$dest"
  ok "二进制就绪"
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
  path_line "安装到" "$dest"
  ok "二进制就绪（本地文件）"
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
    path_line "保留配置" "$path"
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
  path_line "写入" "$path"
  ok "配置已就绪"
}

write_monitor_json() {
  local path="$CONFIG_DIR/monitor.json"
  local server_url="$1" key="$2"
  local machine_id machine_name platform
  machine_id="$(hostname 2>/dev/null || echo linux-host)"
  machine_name="$machine_id"
  platform="linux"
  if [[ -f "$path" && "$FORCE_CONFIG" -eq 0 ]]; then
    path_line "保留配置" "$path"
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
  path_line "写入" "$path"
  ok "配置已就绪"
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
  path_line "单元" "$unit"
  ok "systemd 单元已写入"
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
  path_line "单元" "$unit"
  ok "systemd 单元已写入"
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
  path_line "管理脚本" "$dest"
}

link_shim() {
  local self="$INSTALL_ROOT/install.sh" dest="$LOCAL_BIN/agent-status"
  [[ -f "$self" ]] || return 0
  mkdir -p "$LOCAL_BIN" 2>/dev/null || true
  ln -sfn "$self" "$dest" 2>/dev/null || cp -f "$self" "$dest" 2>/dev/null || true
  if [[ -e "$dest" ]]; then
    chmod +x "$dest" 2>/dev/null || true
    path_line "命令入口" "$dest"
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

  local claude_ok=0 codex_ok=0 W=52
  detect_claude && claude_ok=1
  detect_codex && codex_ok=1

  printf '
'
  box_title_row "$C_A5" "Agent 探测" "$W"
  if [[ "$claude_ok" -eq 1 ]]; then
    box_row "$C_A5" "  ●  Claude Code    已发现  $(pretty_path "$HOME/.claude")" "$W"
  else
    box_row "$C_A5" "  ○  Claude Code    未发现" "$W"
  fi
  if [[ "$codex_ok" -eq 1 ]]; then
    box_row "$C_A5" "  ●  Codex          已发现  $(pretty_path "$HOME/.codex")" "$W"
  else
    box_row "$C_A5" "  ○  Codex          未发现" "$W"
  fi
  box_bot "$C_A5" "$W"

  if [[ "$claude_ok" -eq 1 ]]; then
    info "初始化 Claude Code hooks..."
    local out rc=0
    # 吞掉 slog 原始日志，成功时只展示摘要
    out="$("$mon" --init --claude --config "$cfg" 2>&1)" || rc=$?
    if [[ "$rc" -eq 0 ]]; then
      local settings_path="${HOME}/.claude/settings.json"
      # 尝试从输出提取设置文件路径
      if printf '%s' "$out" | grep -q '设置文件='; then
        settings_path="$(printf '%s' "$out" | sed -n 's/.*设置文件=\([^ ]*\).*/\1/p' | head -n1)"
      fi
      local added updated
      added="$(printf '%s' "$out" | sed -n 's/.*新增事件数=\([0-9]*\).*/\1/p' | head -n1)"
      updated="$(printf '%s' "$out" | sed -n 's/.*更新事件数=\([0-9]*\).*/\1/p' | head -n1)"
      path_line "设置文件" "$settings_path"
      if [[ -n "$added" || -n "$updated" ]]; then
        ok "Claude hooks 已配置  新增 ${added:-0} · 更新 ${updated:-0}"
      else
        ok "Claude hooks 已配置"
      fi
    else
      warn "Claude hooks 初始化失败"
      # 失败时折叠显示原始输出
      if [[ -n "$out" ]]; then
        printf '  %s── 详情 ──────────────────────────────────────────────%s\n' "${C_DIM}" "${C_RESET}"
        printf '%s\n' "$out" | sed 's/^/  │ /'
      fi
    fi
  else
    info "跳过 Claude hooks（未检测到 Claude Code）"
  fi
  if [[ "$codex_ok" -eq 1 ]]; then
    info "Codex 走文件监听，无需额外 hooks"
  fi
}

cmd_status() {
  local r unit active
  local W=52
  printf '
'
  box_top "$C_A3" "$W"
  box_row "$C_A3" "  系统状态" "$W"
  box_bot "$C_A3" "$W"

  while IFS= read -r r; do
    printf '
'
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
  printf '
'
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
  print_banner "卸载"
  local W=52
  ROLE="${ROLE:-all}"

  # 即使二进制已删，也尽量枚举角色
  local roles=()
  if [[ "$ROLE" == "all" || -z "$ROLE" ]]; then
    [[ -x "$BIN_DIR/agent-status-server" || -f "$SYSTEMD_USER_DIR/agent-status-server.service" ]] && roles+=(server)
    [[ -x "$BIN_DIR/agent-status-monitor" || -f "$SYSTEMD_USER_DIR/agent-status-monitor.service" ]] && roles+=(monitor)
    if [[ ${#roles[@]} -eq 0 ]]; then
      roles=(server monitor)
    fi
  else
    roles=("$ROLE")
  fi

  if [[ "$PURGE" -eq 1 ]]; then
    box_top "$C_YELLOW" "$W"
    box_row "$C_YELLOW" "  将彻底删除以下内容：" "$W"
    box_row "$C_YELLOW" "  · 服务单元 / 进程" "$W"
    box_row "$C_YELLOW" "  · 安装目录  $(pretty_path "$INSTALL_ROOT")" "$W"
    box_row "$C_YELLOW" "  · 命令入口  $(pretty_path "$LOCAL_BIN/agent-status")" "$W"
    box_row "$C_YELLOW" "  · 用量游标  ~/.agent-status" "$W"
    box_row "$C_YELLOW" "  · Claude settings 中的 agent-status hooks" "$W"
    box_bot "$C_YELLOW" "$W"
    if ! confirm "确认彻底卸载并清理全部数据"; then
      info "已取消卸载"
      return 0
    fi
  else
    info "标准卸载：停止服务并移除单元，保留安装目录"
    info "彻底清理请加：--purge -y"
  fi

  UI_STEP_CUR=0
  UI_STEP_TOTAL=3
  [[ "$PURGE" -eq 1 ]] && UI_STEP_TOTAL=5

  step "停止并禁用服务"
  local r unit
  for r in "${roles[@]}"; do
    unit="$(unit_for_role "$r" 2>/dev/null || true)"
    [[ -z "$unit" ]] && continue
    systemctl --user disable --now "$unit" 2>/dev/null || true
    # 兜底杀进程
    pkill -f "$BIN_DIR/agent-status-$r" 2>/dev/null || true
    ok "已停止 $r"
  done

  step "移除服务单元"
  for r in "${roles[@]}"; do
    unit="$(unit_for_role "$r" 2>/dev/null || true)"
    [[ -n "$unit" ]] && rm -f "$SYSTEMD_USER_DIR/$unit"
    path_line "已删单元" "$SYSTEMD_USER_DIR/${unit:-$r}"
  done
  systemd_reload
  ok "systemd 用户单元已清理"

  if [[ "$PURGE" -eq 1 ]]; then
    step "删除安装目录与命令入口"
    if [[ -e "$INSTALL_ROOT" ]]; then
      rm -rf "$INSTALL_ROOT"
      path_line "已删除" "$INSTALL_ROOT"
    else
      info "安装目录不存在，跳过"
    fi
    if [[ -L "$LOCAL_BIN/agent-status" || -f "$LOCAL_BIN/agent-status" ]]; then
      rm -f "$LOCAL_BIN/agent-status"
      path_line "已删除" "$LOCAL_BIN/agent-status"
    fi
    ok "安装文件已清理"

    step "清理用量游标与本地状态"
    local as_home="${HOME}/.agent-status"
    if [[ -d "$as_home" ]]; then
      rm -rf "$as_home"
      path_line "已删除" "$as_home"
      ok "用量游标目录已清理"
    else
      info "无 ~/.agent-status，跳过"
    fi

    step "清理 Claude Code hooks"
    remove_claude_hooks || true
  else
    info "已保留安装目录：$(pretty_path "$INSTALL_ROOT")"
    info "配置 / 日志 / 数据库仍在，可再次 install 复用"
  fi

  print_done "卸载完成"
}

remove_claude_hooks() {
  local settings="${HOME}/.claude/settings.json"
  if [[ ! -f "$settings" ]]; then
    info "未找到 Claude settings，跳过 hooks 清理"
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    warn "无 python3，无法自动清理 hooks，请手动编辑 $(pretty_path "$settings")"
    return 0
  fi
  local result
  result="$(python3 - "$settings" <<'PY'
import json, sys, copy, os
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    doc = json.load(f)
hooks = doc.get("hooks")
if not isinstance(hooks, dict):
    print("SKIP|no-hooks")
    raise SystemExit(0)

def is_ours(cmd: str) -> bool:
    c = (cmd or "").replace("\\", "/")
    return "agent-status-monitor" in c and "claude-hook" in c

changed = 0
new_hooks = {}
for event, groups in hooks.items():
    if not isinstance(groups, list):
        new_hooks[event] = groups
        continue
    kept_groups = []
    for g in groups:
        if not isinstance(g, dict):
            kept_groups.append(g)
            continue
        hs = g.get("hooks")
        if not isinstance(hs, list):
            kept_groups.append(g)
            continue
        kept_h = []
        for h in hs:
            if isinstance(h, dict) and is_ours(str(h.get("command", ""))):
                changed += 1
                continue
            kept_h.append(h)
        if kept_h:
            ng = dict(g)
            ng["hooks"] = kept_h
            kept_groups.append(ng)
        else:
            # 整组清空则丢弃
            changed += 0
    if kept_groups:
        new_hooks[event] = kept_groups

if changed == 0:
    print("SKIP|none")
    raise SystemExit(0)

# backup then write
bak = path + ".agent-status.uninstall.bak"
import shutil
shutil.copy2(path, bak)
doc["hooks"] = new_hooks
# drop empty hooks object keys? keep structure
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(doc, f, ensure_ascii=False, indent=2)
    f.write("\n")
os.replace(tmp, path)
print(f"OK|{changed}|{bak}")
PY
)" || true
  case "$result" in
    OK\|*)
      local n bak
      n="$(printf '%s' "$result" | cut -d'|' -f2)"
      bak="$(printf '%s' "$result" | cut -d'|' -f3)"
      path_line "设置文件" "$settings"
      path_line "备份" "$bak"
      ok "已移除 ${n} 条 agent-status hooks"
      ;;
    SKIP\|*)
      info "Claude settings 中无 agent-status hooks"
      ;;
    *)
      warn "清理 hooks 时出现问题，请检查 $(pretty_path "$settings")"
      ;;
  esac
}

cmd_update() {
  print_banner "更新二进制"
  local r target local_ver
  ROLE="${ROLE:-all}"
  target="$(github_release_tag)"
  info "目标版本  $target"
  local roles=()
  while IFS= read -r r; do roles+=("$r"); done < <(roles_expand "$ROLE")
  UI_STEP_CUR=0
  UI_STEP_TOTAL=${#roles[@]}
  local updated=0 skipped=0
  for r in "${roles[@]}"; do
    step "检查 $r"
    local_ver="$(local_binary_version "$r")"
    if [[ -n "$local_ver" ]]; then
      kv "本地" "$local_ver"
    else
      kv "本地" "未知（旧版或未注入版本）"
    fi
    kv "目标" "$target"
    if should_skip_update "$r" "$target"; then
      ok "$r 已是最新（$local_ver），跳过"
      skipped=$((skipped + 1))
      continue
    fi
    info "需要更新，开始下载..."
    # 临时 VERSION，确保 install_binary 拉同一 tag（避免 latest 二次解析漂移）
    local prev_version="$VERSION"
    VERSION="$target"
    systemctl --user stop "$(unit_for_role "$r")" 2>/dev/null || true
    install_binary "$r"
    systemctl --user start "$(unit_for_role "$r")" 2>/dev/null || true
    VERSION="$prev_version"
    local_ver="$(local_binary_version "$r")"
    ok "已更新 $r → ${local_ver:-$target}"
    updated=$((updated + 1))
  done
  if [[ "$updated" -eq 0 && "$skipped" -gt 0 ]]; then
    print_done "已是最新，无需更新"
  else
    print_done "更新完成（更新 ${updated} · 跳过 ${skipped}）" "$INSTALL_ROOT"
  fi
  cmd_status
}

interactive_pick_command() {
  # 无参数交互启动时选择操作
  local W=52 c
  print_banner "管理面板"
  printf '  %s请选择操作%s\n' "${C_BOLD}" "${C_RESET}"
  box_top "$C_DIM" "$W"
  box_row "$C_DIM" "  1  安装 / 重装 install" "$W"
  box_row "$C_DIM" "  2  更新二进制   update" "$W"
  box_row "$C_DIM" "  3  查看状态     status" "$W"
  box_row "$C_DIM" "  4  启动服务     start" "$W"
  box_row "$C_DIM" "  5  停止服务     stop" "$W"
  box_row "$C_DIM" "  6  重启服务     restart" "$W"
  box_row "$C_DIM" "  7  卸载         uninstall" "$W"
  box_row "$C_DIM" "  8  彻底清理     uninstall --purge" "$W"
  box_bot "$C_DIM" "$W"
  c="$(prompt "请输入序号" "1")"
  case "$c" in
    1) CMD="install" ;;
    2) CMD="update" ;;
    3) CMD="status" ;;
    4) CMD="start" ;;
    5) CMD="stop" ;;
    6) CMD="restart" ;;
    7) CMD="uninstall"; PURGE=0 ;;
    8)
      CMD="uninstall"
      PURGE=1
      ;;
    *) die "无效选项: $c" ;;
  esac
  # 需要角色的命令：未指定时默认 all（安装仍会再问）
  case "$CMD" in
    update|status|start|stop|restart|enable|disable)
      [[ -z "$ROLE" ]] && ROLE="all"
      ;;
    uninstall)
      [[ -z "$ROLE" ]] && ROLE="all"
      ;;
  esac
}


interactive_fill() {
  local want_server=0 want_monitor=0
  local keep_server=0 keep_monitor=0
  local existing_url="" existing_key="" default_url="http://127.0.0.1:29125"

  if [[ -z "$ROLE" ]]; then
    have_tty || die "非交互安装请指定 --role 与 --yes"
    local W=52
    printf '  %s选择要安装的角色%s
' "${C_BOLD}" "${C_RESET}"
    box_top "$C_DIM" "$W"
    box_row "$C_DIM" "  1  服务端 server     接收上报 / WebSocket / API" "$W"
    box_row "$C_DIM" "  2  监测端 monitor    扫描会话与用量并上报" "$W"
    box_row "$C_DIM" "  3  两者都装 all      本机完整部署" "$W"
    box_bot "$C_DIM" "$W"
    # 默认：已有服务端且无监测端 → 服务端；仅有监测端 → 监测端；否则不默认强行装监测端
    local def_role=""
    if [[ -f "$CONFIG_DIR/server.env" && ! -f "$CONFIG_DIR/monitor.json" ]]; then
      def_role="1"
    elif [[ -f "$CONFIG_DIR/monitor.json" && ! -f "$CONFIG_DIR/server.env" ]]; then
      def_role="2"
    elif [[ -f "$CONFIG_DIR/server.env" && -f "$CONFIG_DIR/monitor.json" ]]; then
      def_role="3"
    fi
    local c
    if [[ -n "$def_role" ]]; then
      c="$(prompt "请输入序号" "$def_role")"
    else
      c="$(prompt "请输入序号" "")"
      [[ -n "$c" ]] || die "请选择角色 1/2/3"
    fi
    case "$c" in
      1) ROLE=server ;;
      2) ROLE=monitor ;;
      3) ROLE=all ;;
      *) die "无效选项: $c" ;;
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
      --force) FORCE_UPDATE=1; shift ;;
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
  local argc=$#
  parse_args "$@"
  # 无参数 + 交互终端：弹出操作菜单（含卸载）
  if [[ "$argc" -eq 0 ]] && have_tty && [[ "$YES" -eq 0 ]]; then
    interactive_pick_command
  fi
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
