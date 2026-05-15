#!/usr/bin/env bash
# lib/common.sh — Shared library for all DevOps scripts
# Source this file: source "$(dirname "$0")/../lib/common.sh"

# Guard against double-sourcing
[[ -n "${_COMMON_SH_LOADED:-}" ]] && return 0
_COMMON_SH_LOADED=1

set -Eeuo pipefail

# ---------------------------------------------------------------------------
# COLORS & LOGGING
# ---------------------------------------------------------------------------
_init_colors() {
  if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    BOLD="$(tput bold 2>/dev/null || true)"
    DIM="$(tput dim 2>/dev/null || true)"
    RESET="$(tput sgr0 2>/dev/null || true)"
    RED="$(tput setaf 1 2>/dev/null || true)"
    GREEN="$(tput setaf 2 2>/dev/null || true)"
    YELLOW="$(tput setaf 3 2>/dev/null || true)"
    BLUE="$(tput setaf 4 2>/dev/null || true)"
    MAGENTA="$(tput setaf 5 2>/dev/null || true)"
    CYAN="$(tput setaf 6 2>/dev/null || true)"
    WHITE="$(tput setaf 7 2>/dev/null || true)"
  else
    BOLD="" DIM="" RESET="" RED="" GREEN="" YELLOW=""
    BLUE="" MAGENTA="" CYAN="" WHITE=""
  fi
  export BOLD DIM RESET RED GREEN YELLOW BLUE MAGENTA CYAN WHITE
}
_init_colors

log_info()  { echo "${CYAN}${BOLD}[INFO]${RESET}  $*"; }
log_ok()    { echo "${GREEN}${BOLD}[ OK ]${RESET}  $*"; }
log_warn()  { echo "${YELLOW}${BOLD}[WARN]${RESET}  $*"; }
log_error() { echo "${RED}${BOLD}[ERR ]${RESET}  $*" >&2; }
log_step()  { echo "${BLUE}${BOLD}[STEP]${RESET}  $*"; }
log_debug() { [[ "${DEBUG:-0}" == "1" ]] && echo "${DIM}[DBG]  $*${RESET}" || true; }

pause() { read -r -p "${DIM}Press Enter to continue...${RESET} " _ || true; }
press_enter() { pause; }

# ---------------------------------------------------------------------------
# OS & PACKAGE MANAGER DETECTION
# ---------------------------------------------------------------------------
OS_ID=""
OS_ID_LIKE=""
OS_VERSION_ID=""
OS_PRETTY_NAME=""
PKG_MANAGER=""
PKG_INSTALL=""
PKG_UPDATE=""
PKG_REMOVE=""
PKG_QUERY=""
ARCH=""
SHELL_NAME=""

detect_os() {
  ARCH="$(uname -m)"
  SHELL_NAME="$(basename "${SHELL:-bash}")"

  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_ID_LIKE="${ID_LIKE:-}"
    OS_VERSION_ID="${VERSION_ID:-}"
    OS_PRETTY_NAME="${PRETTY_NAME:-Linux}"
  elif [[ -f /etc/redhat-release ]]; then
    OS_ID="rhel"
    OS_PRETTY_NAME="$(cat /etc/redhat-release)"
  elif [[ -f /etc/alpine-release ]]; then
    OS_ID="alpine"
    OS_PRETTY_NAME="Alpine Linux $(cat /etc/alpine-release)"
  else
    OS_ID="unknown"
    OS_PRETTY_NAME="Unknown Linux"
  fi

  export OS_ID OS_ID_LIKE OS_VERSION_ID OS_PRETTY_NAME ARCH SHELL_NAME
}

detect_package_manager() {
  detect_os
  if command -v apt-get >/dev/null 2>&1; then
    PKG_MANAGER="apt"
    PKG_INSTALL="apt-get install -y"
    PKG_UPDATE="apt-get update -y"
    PKG_REMOVE="apt-get remove -y"
    PKG_QUERY="dpkg -l"
  elif command -v dnf >/dev/null 2>&1; then
    PKG_MANAGER="dnf"
    PKG_INSTALL="dnf install -y"
    PKG_UPDATE="dnf check-update || true"
    PKG_REMOVE="dnf remove -y"
    PKG_QUERY="rpm -q"
  elif command -v yum >/dev/null 2>&1; then
    PKG_MANAGER="yum"
    PKG_INSTALL="yum install -y"
    PKG_UPDATE="yum check-update || true"
    PKG_REMOVE="yum remove -y"
    PKG_QUERY="rpm -q"
  elif command -v pacman >/dev/null 2>&1; then
    PKG_MANAGER="pacman"
    PKG_INSTALL="pacman -S --noconfirm"
    PKG_UPDATE="pacman -Sy"
    PKG_REMOVE="pacman -R --noconfirm"
    PKG_QUERY="pacman -Q"
  elif command -v zypper >/dev/null 2>&1; then
    PKG_MANAGER="zypper"
    PKG_INSTALL="zypper install -y"
    PKG_UPDATE="zypper refresh"
    PKG_REMOVE="zypper remove -y"
    PKG_QUERY="rpm -q"
  elif command -v apk >/dev/null 2>&1; then
    PKG_MANAGER="apk"
    PKG_INSTALL="apk add"
    PKG_UPDATE="apk update"
    PKG_REMOVE="apk del"
    PKG_QUERY="apk info"
  else
    PKG_MANAGER="unknown"
    PKG_INSTALL=""
    PKG_UPDATE=""
    PKG_REMOVE=""
    PKG_QUERY=""
    log_warn "No supported package manager found."
    return 1
  fi
  export PKG_MANAGER PKG_INSTALL PKG_UPDATE PKG_REMOVE PKG_QUERY
}

is_apt_based() {
  detect_package_manager 2>/dev/null || true
  [[ "$PKG_MANAGER" == "apt" ]]
}

is_rpm_based() {
  detect_package_manager 2>/dev/null || true
  [[ "$PKG_MANAGER" == "dnf" || "$PKG_MANAGER" == "yum" ]]
}

is_arch_based() {
  detect_package_manager 2>/dev/null || true
  [[ "$PKG_MANAGER" == "pacman" ]]
}

# ---------------------------------------------------------------------------
# PACKAGE INSTALLATION
# ---------------------------------------------------------------------------
install_package() {
  local pkg="$1"
  detect_package_manager 2>/dev/null || true

  if [[ -z "$PKG_INSTALL" ]]; then
    log_error "Cannot install '$pkg': no package manager detected."
    return 1
  fi

  log_step "Installing package: $pkg"
  # shellcheck disable=SC2086
  run_cmd sudo $PKG_INSTALL "$pkg"
}

# Update package index
update_package_index() {
  detect_package_manager 2>/dev/null || true
  [[ -z "$PKG_UPDATE" ]] && return 1
  log_step "Updating package index..."
  # shellcheck disable=SC2086
  run_cmd sudo $PKG_UPDATE
}

# ---------------------------------------------------------------------------
# COMMAND REQUIREMENTS
# ---------------------------------------------------------------------------
require_command() {
  local cmd="$1"
  local hint="${2:-}"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log_error "Required command not found: $cmd"
    [[ -n "$hint" ]] && log_info "Install hint: $hint"
    return 1
  fi
}

is_installed() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# SUDO / ROOT
# ---------------------------------------------------------------------------
check_sudo() {
  if [[ $EUID -eq 0 ]]; then
    return 0
  fi
  if ! command -v sudo >/dev/null 2>&1; then
    log_error "sudo is not installed. Run as root or install sudo."
    return 1
  fi
  if ! sudo -n true 2>/dev/null; then
    log_info "This operation requires sudo. You may be prompted for your password."
    if ! sudo true; then
      log_error "Failed to obtain sudo privileges."
      return 1
    fi
  fi
}

require_root() {
  if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root or with sudo."
    log_info "Try: sudo $0"
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# INTERNET CHECK
# ---------------------------------------------------------------------------
check_internet() {
  local hosts=("1.1.1.1" "8.8.8.8" "github.com")
  for h in "${hosts[@]}"; do
    if ping -c 1 -W 2 "$h" >/dev/null 2>&1; then
      return 0
    fi
  done
  # Fallback: try curl
  if command -v curl >/dev/null 2>&1; then
    if curl -fsSL --max-time 5 https://github.com >/dev/null 2>&1; then
      return 0
    fi
  fi
  return 1
}

require_internet() {
  log_info "Checking internet connectivity..."
  if ! check_internet; then
    log_error "No internet connection detected. Please check your network."
    exit 1
  fi
  log_ok "Internet connection OK."
}

# ---------------------------------------------------------------------------
# USER INPUT HELPERS
# ---------------------------------------------------------------------------

# ask_input "Prompt" "default_value"
ask_input() {
  local prompt="$1"
  local default="${2:-}"
  local value
  if [[ -n "$default" ]]; then
    read -r -p "${CYAN}${prompt}${RESET} [${DIM}${default}${RESET}]: " value
    echo "${value:-$default}"
  else
    read -r -p "${CYAN}${prompt}${RESET}: " value
    echo "$value"
  fi
}

# ask_secret "Prompt" — masked input, no echo
ask_secret() {
  local prompt="$1"
  local value
  read -r -s -p "${CYAN}${prompt}${RESET}: " value
  echo
  echo "$value"
}

# ask_confirm "Question" → returns 0 (yes) or 1 (no)
ask_confirm() {
  local prompt="${1:-Are you sure?}"
  local answer
  read -r -p "${YELLOW}${prompt}${RESET} [y/N]: " answer
  [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}

# ask_confirm_default_yes "Question" → default is Yes
ask_confirm_yes() {
  local prompt="${1:-Continue?}"
  local answer
  read -r -p "${YELLOW}${prompt}${RESET} [Y/n]: " answer
  [[ -z "$answer" || "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}

# choose_option "Title" option1 option2 ...
# Returns selected index (1-based) in REPLY
choose_option() {
  local title="$1"
  shift
  local options=("$@")
  echo
  echo "${BOLD}${title}${RESET}"
  local i=1
  for opt in "${options[@]}"; do
    echo "  ${CYAN}${i})${RESET} $opt"
    ((i++))
  done
  echo "  ${CYAN}0)${RESET} Cancel / Back"
  echo
  local choice
  read -r -p "Choose [0-$((i-1))]: " choice
  REPLY="${choice:-0}"
}

# ---------------------------------------------------------------------------
# DIALOG SUPPORT (with fallback)
# ---------------------------------------------------------------------------
DIALOG_AVAILABLE=0
_check_dialog() {
  if command -v dialog >/dev/null 2>&1; then
    DIALOG_AVAILABLE=1
  else
    DIALOG_AVAILABLE=0
  fi
}
_check_dialog

offer_install_dialog() {
  if [[ "$DIALOG_AVAILABLE" -eq 1 ]]; then return 0; fi
  log_warn "'dialog' is not installed. Install it for a better interactive menu."
  if ask_confirm "Install dialog now?"; then
    detect_package_manager 2>/dev/null || true
    if [[ -n "$PKG_INSTALL" ]]; then
      # shellcheck disable=SC2086
      sudo $PKG_INSTALL dialog && DIALOG_AVAILABLE=1
    else
      log_warn "Cannot install dialog automatically. Falling back to text menu."
    fi
  fi
}

# menu_select "Title" "Back label" "1:Label" "2:Label" ...
# Returns selected key in REPLY. Uses dialog when available, otherwise text.
menu_select() {
  local title="$1"
  local back_label="$2"
  shift 2
  local -a items=("$@")
  local choice=""

  if command -v dialog >/dev/null 2>&1; then
    local tmp
    tmp="$(make_tmpfile)"
    local -a dialog_items=()
    local item
    for item in "${items[@]}"; do
      dialog_items+=("${item%%:*}" "${item#*:}")
    done
    dialog_items+=("0" "$back_label")
    if dialog --clear --title "$title" --menu "${SCRIPT_DESC:-Choose an option}" 22 76 14 "${dialog_items[@]}" 2>"$tmp"; then
      choice="$(<"$tmp")"
    else
      choice="0"
    fi
    clear || true
  else
    echo
    echo "${BOLD}${title}${RESET}"
    local item
    for item in "${items[@]}"; do
      printf "  ${CYAN}%s)${RESET} %s\n" "${item%%:*}" "${item#*:}"
    done
    echo "  ${CYAN}0)${RESET} ${back_label}"
    echo
    read -r -p "Choose: " choice
  fi

  REPLY="${choice:-0}"
}

# ---------------------------------------------------------------------------
# COMMAND EXECUTION WITH LOGGING
# ---------------------------------------------------------------------------
DRY_RUN="${DRY_RUN:-0}"

run_cmd() {
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[DRY-RUN] Would run: $*"
    return 0
  fi
  log_debug "Running: $*"
  "$@"
}

run_cmd_sudo() {
  if [[ "$DRY_RUN" == "1" ]]; then
    log_info "[DRY-RUN] Would run (sudo): $*"
    return 0
  fi
  log_debug "Running (sudo): $*"
  sudo "$@"
}

# ---------------------------------------------------------------------------
# FILE & BACKUP HELPERS
# ---------------------------------------------------------------------------
backup_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    log_warn "Cannot backup (file not found): $file"
    return 1
  fi
  local backup="${file}.bak.$(date +'%Y%m%d_%H%M%S')"
  cp "$file" "$backup"
  log_ok "Backed up: $file -> $backup"
}

# ---------------------------------------------------------------------------
# CLEANUP ON EXIT (trap handler)
# ---------------------------------------------------------------------------
_TMPFILES=()

cleanup_on_exit() {
  local exit_code=$?
  for f in "${_TMPFILES[@]}"; do
    [[ -e "$f" ]] && rm -rf "$f" && log_debug "Cleaned up temp: $f"
  done
  if [[ $exit_code -ne 0 ]]; then
    log_error "Script exited with error code: $exit_code"
  fi
}

register_cleanup() {
  trap 'cleanup_on_exit' EXIT INT TERM ERR
}

make_tmpfile() {
  local tmp
  tmp="$(mktemp)"
  _TMPFILES+=("$tmp")
  echo "$tmp"
}

make_tmpdir() {
  local tmp
  tmp="$(mktemp -d)"
  _TMPFILES+=("$tmp")
  echo "$tmp"
}

# ---------------------------------------------------------------------------
# SCRIPT HEADER
# ---------------------------------------------------------------------------
print_script_header() {
  local name="$1"
  local description="$2"
  detect_os
  detect_package_manager 2>/dev/null || true

  clear || true
  echo "${BOLD}${MAGENTA}╔══════════════════════════════════════════════════════════╗${RESET}"
  printf "${BOLD}${MAGENTA}║  %-56s  ║${RESET}\n" "$name"
  printf "${BOLD}${MAGENTA}║  %-56s  ║${RESET}\n" "$description"
  echo "${BOLD}${MAGENTA}╚══════════════════════════════════════════════════════════╝${RESET}"
  echo
  echo "${DIM}  OS       : ${OS_PRETTY_NAME} (${ARCH})${RESET}"
  echo "${DIM}  Pkg Mgr  : ${PKG_MANAGER:-unknown}${RESET}"
  echo "${DIM}  Shell    : ${SHELL_NAME}${RESET}"
  echo "${DIM}  User     : $(whoami) | Host: $(hostname)${RESET}"
  echo "${DIM}  Date     : $(date +'%Y-%m-%d %H:%M:%S')${RESET}"
  [[ "${DRY_RUN:-0}" == "1" ]] && echo "${YELLOW}  [DRY-RUN MODE ENABLED]${RESET}"
  echo
}

print_menu_separator() {
  echo "${DIM}──────────────────────────────────────────────────────────${RESET}"
}

# ---------------------------------------------------------------------------
# ENVIRONMENT CHECKS
# ---------------------------------------------------------------------------
check_prerequisites() {
  local -a required_cmds=("$@")
  local missing=0
  for cmd in "${required_cmds[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
      log_ok "Found: $cmd ($(command -v "$cmd"))"
    else
      log_warn "Missing: $cmd"
      ((missing++))
    fi
  done
  return $missing
}

show_env_info() {
  detect_os
  detect_package_manager 2>/dev/null || true
  echo
  log_info "=== Environment Information ==="
  echo "  OS          : ${OS_PRETTY_NAME}"
  echo "  OS ID       : ${OS_ID} (like: ${OS_ID_LIKE:-none})"
  echo "  Version     : ${OS_VERSION_ID:-unknown}"
  echo "  Architecture: ${ARCH}"
  echo "  Shell       : ${SHELL_NAME}"
  echo "  Pkg Manager : ${PKG_MANAGER:-unknown}"
  echo "  User        : $(whoami) (UID: $EUID)"
  echo "  Hostname    : $(hostname)"
  echo "  Kernel      : $(uname -r)"
  echo "  Internet    : $(check_internet && echo "OK" || echo "NOT reachable")"
  echo "  Sudo        : $(sudo -n true 2>/dev/null && echo "passwordless" || echo "requires password")"
  echo
}

show_script_usage() {
  local script_name="${SCRIPT_NAME:-$(basename "$0")}"
  local script_desc="${SCRIPT_DESC:-Interactive Linux toolbox script}"
  cat <<EOF
${BOLD}Usage:${RESET} $0 [options]

${BOLD}${script_name}${RESET}
  ${script_desc}

${BOLD}Options:${RESET}
  --dry-run     Enable dry-run mode where supported
  --check-env   Print environment information and exit
  --help, -h    Show this help message
EOF
}

handle_standard_args() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      --dry-run)
        export DRY_RUN=1
        ;;
      --check-env)
        show_env_info
        exit 0
        ;;
      --help|-h)
        show_script_usage
        exit 0
        ;;
      "")
        ;;
      *)
        log_warn "Unknown argument: $arg"
        ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# VERSION HELPERS
# ---------------------------------------------------------------------------
version_gte() {
  # usage: version_gte "1.20" "1.19" → true if $1 >= $2
  printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

# ---------------------------------------------------------------------------
# ARCH HELPERS
# ---------------------------------------------------------------------------
get_arch_suffix() {
  case "$(uname -m)" in
    x86_64)  echo "amd64" ;;
    aarch64) echo "arm64" ;;
    armv7l)  echo "armv7" ;;
    i386|i686) echo "386" ;;
    *)       echo "amd64" ;;
  esac
}

get_arch_uname() {
  uname -m
}

# ---------------------------------------------------------------------------
# DOWNLOAD HELPER
# ---------------------------------------------------------------------------
download_file() {
  local url="$1"
  local dest="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$dest" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$dest" "$url"
  else
    log_error "Neither curl nor wget is available. Cannot download file."
    return 1
  fi
}

# ---------------------------------------------------------------------------
# SYSTEMD HELPERS
# ---------------------------------------------------------------------------
systemd_available() { command -v systemctl >/dev/null 2>&1; }

service_enable_start() {
  local svc="$1"
  if systemd_available; then
    run_cmd_sudo systemctl enable --now "$svc"
    log_ok "Service enabled and started: $svc"
  else
    log_warn "systemd not available. Cannot manage service: $svc"
  fi
}

service_status() {
  local svc="$1"
  if systemd_available; then
    systemctl status "$svc" --no-pager -l || true
  fi
}

service_is_active() {
  local svc="$1"
  systemd_available && systemctl is-active --quiet "$svc" 2>/dev/null
}

# ---------------------------------------------------------------------------
# MISC UTILITIES
# ---------------------------------------------------------------------------
require_not_empty() {
  local value="$1"
  local name="${2:-value}"
  if [[ -z "$value" ]]; then
    log_error "$name cannot be empty."
    return 1
  fi
}

valid_linux_name() {
  [[ "${1:-}" =~ ^[a-z_][a-z0-9_-]*$ ]]
}

user_exists()  { getent passwd "$1" >/dev/null 2>&1; }
group_exists() { getent group  "$1" >/dev/null 2>&1; }

port_in_use() { ss -tlnp 2>/dev/null | grep -q ":${1} " || true; }

hr() {
  echo "${DIM}$(printf '─%.0s' {1..60})${RESET}"
}
