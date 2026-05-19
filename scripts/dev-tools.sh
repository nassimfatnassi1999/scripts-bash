#!/usr/bin/env bash
# scripts/dev-tools.sh — Developer tools installer
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
register_cleanup

SCRIPT_NAME="Dev Tools Installer"
SCRIPT_DESC="Install common developer toolchains and CLI utilities"

handle_standard_args "$@"

install_packages() {
  check_sudo || return 1
  detect_package_manager || return 1
  case "$PKG_MANAGER" in
    apt) run_cmd_sudo apt-get update -y; run_cmd_sudo apt-get install -y "$@" ;;
    dnf|yum) run_cmd_sudo "$PKG_MANAGER" install -y "$@" ;;
    pacman) run_cmd_sudo pacman -S --noconfirm "$@" ;;
    zypper) run_cmd_sudo zypper install -y "$@" ;;
    apk) run_cmd_sudo apk add "$@" ;;
    *) log_error "Unsupported package manager."; return 1 ;;
  esac
}

install_core_tools() {
  detect_package_manager || return 1
  case "$PKG_MANAGER" in
    apt) install_packages build-essential curl wget git ca-certificates gnupg unzip jq make pkg-config ;;
    dnf|yum) install_packages gcc gcc-c++ make curl wget git ca-certificates gnupg2 unzip jq pkgconfig ;;
    pacman) install_packages base-devel curl wget git ca-certificates gnupg unzip jq pkgconf ;;
    zypper) install_packages patterns-devel-base-devel_basis curl wget git ca-certificates gpg2 unzip jq pkg-config ;;
    apk) install_packages build-base curl wget git ca-certificates gnupg unzip jq pkgconf ;;
  esac
}

install_python() {
  detect_package_manager || return 1
  case "$PKG_MANAGER" in
    apt) install_packages python3 python3-pip python3-venv pipx ;;
    dnf|yum) install_packages python3 python3-pip pipx ;;
    pacman) install_packages python python-pip python-pipx ;;
    zypper) install_packages python3 python3-pip python3-pipx ;;
    apk) install_packages python3 py3-pip pipx ;;
  esac
}

install_node() {
  detect_package_manager || return 1
  case "$PKG_MANAGER" in
    apt) install_packages nodejs npm ;;
    dnf|yum) install_packages nodejs npm ;;
    pacman) install_packages nodejs npm ;;
    zypper) install_packages nodejs npm ;;
    apk) install_packages nodejs npm ;;
  esac
}

install_go() {
  detect_package_manager || return 1
  case "$PKG_MANAGER" in
    apt) install_packages golang ;;
    dnf|yum) install_packages golang ;;
    pacman) install_packages go ;;
    zypper) install_packages go ;;
    apk) install_packages go ;;
  esac
}

install_rust() {
  require_internet
  if command -v rustup >/dev/null 2>&1; then
    run_cmd rustup update
  else
    log_warn "This downloads and runs the official rustup installer."
    if ask_confirm "Install Rust with rustup?"; then
      if [[ "${DRY_RUN:-0}" == "1" ]]; then
        log_info "[DRY-RUN] Would run rustup installer."
      else
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
      fi
    fi
  fi
}

install_shell_tools() {
  detect_package_manager || return 1
  case "$PKG_MANAGER" in
    apt) install_packages shellcheck shfmt ripgrep fd-find bat fzf tree tmux ;;
    dnf|yum) install_packages ShellCheck shfmt ripgrep fd-find bat fzf tree tmux ;;
    pacman) install_packages shellcheck shfmt ripgrep fd bat fzf tree tmux ;;
    zypper) install_packages ShellCheck shfmt ripgrep fd bat fzf tree tmux ;;
    apk) install_packages shellcheck shfmt ripgrep fd bat fzf tree tmux ;;
  esac
}

show_versions() {
  local -a tools=(git curl wget jq make gcc python3 pip3 node npm go rustc cargo shellcheck shfmt rg fd bat fzf tmux)
  local tool
  for tool in "${tools[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
      printf "%-12s %s\n" "$tool" "$("$tool" --version 2>&1 | head -1)"
    else
      printf "%-12s %s\n" "$tool" "missing"
    fi
  done
}

install_all() {
  install_core_tools || true
  install_python || true
  install_node || true
  install_go || true
  install_shell_tools || true
}

main_menu_choice() {
  menu_select "$SCRIPT_NAME" "Exit" \
    "1:Show tool versions" \
    "2:Install core build tools" \
    "3:Install Python tools" \
    "4:Install Node.js tools" \
    "5:Install Go" \
    "6:Install Rust with rustup" \
    "7:Install shell productivity tools" \
    "8:Install all package-manager tools" \
    "e:Show environment info"
}

main() {
  while true; do
    print_script_header "$SCRIPT_NAME" "$SCRIPT_DESC"
    main_menu_choice
    echo
    case "${REPLY:-}" in
      1) show_versions || true; pause ;;
      2) install_core_tools || true; pause ;;
      3) install_python || true; pause ;;
      4) install_node || true; pause ;;
      5) install_go || true; pause ;;
      6) install_rust || true; pause ;;
      7) install_shell_tools || true; pause ;;
      8) install_all || true; pause ;;
      e|E) show_env_info; pause ;;
      0) log_info "Bye!"; exit 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

main "$@"
