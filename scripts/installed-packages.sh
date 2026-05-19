#!/usr/bin/env bash
# scripts/installed-packages.sh — List, export and import packages
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
register_cleanup

SCRIPT_NAME="Installed Packages Manager"
SCRIPT_DESC="List, export, import and audit installed packages"

handle_standard_args "$@"

EXPORT_DIR="${HOME}/package-exports"

# ---------------------------------------------------------------------------
# APT
# ---------------------------------------------------------------------------
list_apt_recent() {
  log_info "=== Recent APT installations ==="
  if [[ -f /var/log/apt/history.log ]]; then
    zgrep -h "Install:" /var/log/apt/history.log* 2>/dev/null | tail -n 30
  else
    log_warn "No apt history found."
  fi
}

list_dpkg_recent() {
  log_info "=== Recent DPKG installs ==="
  if [[ -f /var/log/dpkg.log ]]; then
    zgrep -h " install " /var/log/dpkg.log* 2>/dev/null | tail -n 30
  else
    log_warn "No dpkg log found."
  fi
}

list_apt_all() {
  log_info "=== All manually installed packages (apt) ==="
  if is_installed apt-mark; then
    apt-mark showmanual | sort
  else
    dpkg --get-selections | grep -v deinstall | awk '{print $1}' | sort
  fi
}

export_apt() {
  mkdir -p "$EXPORT_DIR"
  local outfile="${EXPORT_DIR}/apt-packages-$(date +'%Y%m%d_%H%M%S').txt"
  if is_installed apt-mark; then
    apt-mark showmanual | sort > "$outfile"
  else
    dpkg --get-selections | grep -v deinstall | awk '{print $1}' > "$outfile"
  fi
  log_ok "APT packages exported to: $outfile"
}

import_apt() {
  local infile
  infile="$(ask_input "Package list file path")"
  [[ ! -f "$infile" ]] && { log_error "File not found: $infile"; return 1; }
  check_sudo || return 1
  log_step "Installing packages from: $infile"
  if ask_confirm "Preview packages first?"; then
    cat "$infile"
    echo
  fi
  if ask_confirm "Install all packages from $infile?"; then
    run_cmd_sudo apt-get update -y
    # shellcheck disable=SC2046
    run_cmd_sudo apt-get install -y $(cat "$infile")
    log_ok "Packages installed."
  fi
}

# ---------------------------------------------------------------------------
# DNF/YUM
# ---------------------------------------------------------------------------
list_rpm_all() {
  log_info "=== All installed RPM packages ==="
  rpm -qa --qf "%{NAME}\n" | sort
}

export_rpm() {
  mkdir -p "$EXPORT_DIR"
  local outfile="${EXPORT_DIR}/rpm-packages-$(date +'%Y%m%d_%H%M%S').txt"
  rpm -qa --qf "%{NAME}\n" | sort > "$outfile"
  log_ok "RPM packages exported to: $outfile"
}

import_rpm() {
  local infile
  infile="$(ask_input "Package list file path")"
  [[ ! -f "$infile" ]] && { log_error "File not found: $infile"; return 1; }
  check_sudo || return 1
  if ask_confirm "Install all packages from $infile?"; then
    # shellcheck disable=SC2046
    run_cmd sudo "$PKG_MANAGER" install -y $(cat "$infile")
    log_ok "Packages installed."
  fi
}

# ---------------------------------------------------------------------------
# PACMAN
# ---------------------------------------------------------------------------
list_pacman_all() {
  log_info "=== Explicitly installed packages (pacman) ==="
  pacman -Qe | sort
}

export_pacman() {
  mkdir -p "$EXPORT_DIR"
  local outfile="${EXPORT_DIR}/pacman-packages-$(date +'%Y%m%d_%H%M%S').txt"
  pacman -Qe | awk '{print $1}' | sort > "$outfile"
  log_ok "Pacman packages exported to: $outfile"
}

import_pacman() {
  local infile
  infile="$(ask_input "Package list file path")"
  [[ ! -f "$infile" ]] && { log_error "File not found: $infile"; return 1; }
  if ask_confirm "Install all packages from $infile?"; then
    # shellcheck disable=SC2046
    run_cmd_sudo pacman -S --noconfirm $(cat "$infile")
    log_ok "Packages installed."
  fi
}

# ---------------------------------------------------------------------------
# SNAP
# ---------------------------------------------------------------------------
list_snap() {
  if is_installed snap; then
    log_info "=== Snap packages ==="
    snap list
  else
    log_warn "snap is not installed."
  fi
}

export_snap() {
  if ! is_installed snap; then log_warn "snap not installed."; return 0; fi
  mkdir -p "$EXPORT_DIR"
  local outfile="${EXPORT_DIR}/snap-packages-$(date +'%Y%m%d_%H%M%S').txt"
  snap list | awk 'NR>1{print $1}' | sort > "$outfile"
  log_ok "Snap packages exported to: $outfile"
}

# ---------------------------------------------------------------------------
# FLATPAK
# ---------------------------------------------------------------------------
list_flatpak() {
  if is_installed flatpak; then
    log_info "=== Flatpak packages ==="
    flatpak list --app --columns=application | sort
  else
    log_warn "flatpak is not installed."
  fi
}

export_flatpak() {
  if ! is_installed flatpak; then log_warn "flatpak not installed."; return 0; fi
  mkdir -p "$EXPORT_DIR"
  local outfile="${EXPORT_DIR}/flatpak-packages-$(date +'%Y%m%d_%H%M%S').txt"
  flatpak list --app --columns=application | sort > "$outfile"
  log_ok "Flatpak packages exported to: $outfile"
}

# ---------------------------------------------------------------------------
# SHELL HISTORY
# ---------------------------------------------------------------------------
show_shell_history_installs() {
  log_info "=== Package installs from shell history ==="
  local histfile="${HISTFILE:-${HOME}/.bash_history}"
  [[ -f "${HOME}/.zsh_history" ]] && histfile="${HOME}/.zsh_history"
  if [[ -f "$histfile" ]]; then
    grep -E "(apt|dnf|yum|pacman|zypper|apk|snap|flatpak).*(install)" "$histfile" 2>/dev/null | tail -20 || true
  else
    log_warn "No shell history file found."
  fi
}

# ---------------------------------------------------------------------------
# AUDIT: LARGEST PACKAGES
# ---------------------------------------------------------------------------
show_largest_packages() {
  detect_package_manager || return 1
  log_info "=== Largest installed packages ==="
  case "$PKG_MANAGER" in
    apt)
      if is_installed dpkg-query; then
        dpkg-query --show --showformat='${Installed-Size}\t${Package}\n' 2>/dev/null \
          | sort -rn | head -20 | awk '{printf "%-10s %s\n", $1"K", $2}'
      fi
      ;;
    dnf|yum)
      rpm -qa --qf '%{SIZE}\t%{NAME}\n' | sort -rn | head -20 | \
        awk '{printf "%-10s %s\n", $1, $2}'
      ;;
    pacman)
      pacman -Qi | awk '/^Name/{name=$3} /^Installed Size/{print $4$5, name}' \
        | sort -h -r | head -20
      ;;
    *)
      log_warn "Largest packages audit not supported for $PKG_MANAGER"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# UNIFIED EXPORT / IMPORT (auto-detect)
# ---------------------------------------------------------------------------
do_export_all() {
  detect_package_manager || return 1
  mkdir -p "$EXPORT_DIR"
  log_step "Exporting packages to: $EXPORT_DIR"
  case "$PKG_MANAGER" in
    apt)    export_apt ;;
    dnf|yum) export_rpm ;;
    pacman) export_pacman ;;
    *) log_warn "Auto-export not supported for: $PKG_MANAGER" ;;
  esac
  export_snap
  export_flatpak
  log_ok "Export complete. Files in: $EXPORT_DIR"
}

# ---------------------------------------------------------------------------
# MENU
# ---------------------------------------------------------------------------
main() {
  detect_package_manager || return 1

  while true; do
    print_script_header "$SCRIPT_NAME" "$SCRIPT_DESC"
    echo "  ${DIM}Package manager: ${PKG_MANAGER}${RESET}"
    echo "  ${DIM}Export directory: ${EXPORT_DIR}${RESET}"
    echo
    echo "  ${BOLD}${YELLOW}List Packages${RESET}"
    echo "  ${CYAN}1)${RESET}  List packages (auto-detect)"
    echo "  ${CYAN}2)${RESET}  Recent APT installs (from logs)"
    echo "  ${CYAN}3)${RESET}  Snap packages"
    echo "  ${CYAN}4)${RESET}  Flatpak packages"
    echo "  ${CYAN}5)${RESET}  Installs from shell history"
    echo "  ${CYAN}6)${RESET}  Largest installed packages"
    print_menu_separator
    echo "  ${BOLD}${YELLOW}Export / Import${RESET}"
    echo "  ${CYAN}7)${RESET}  Export packages (auto-detect)"
    echo "  ${CYAN}8)${RESET}  Export Snap packages"
    echo "  ${CYAN}9)${RESET}  Export Flatpak packages"
    echo "  ${CYAN}10)${RESET} Import packages from file"
    print_menu_separator
    echo "  ${CYAN}e)${RESET}  Show environment info"
    echo "  ${CYAN}0)${RESET}  Exit"
    echo
    read -r -p "Choose: " c
    echo
    case "${c:-}" in
      1)
        case "$PKG_MANAGER" in
          apt)    list_apt_all || true ;;
          dnf|yum) list_rpm_all || true ;;
          pacman) list_pacman_all || true ;;
          *) log_warn "List not supported for $PKG_MANAGER" ;;
        esac
        pause
        ;;
      2)  list_apt_recent || true; list_dpkg_recent || true; pause ;;
      3)  list_snap || true; pause ;;
      4)  list_flatpak || true; pause ;;
      5)  show_shell_history_installs || true; pause ;;
      6)  show_largest_packages || true; pause ;;
      7)  do_export_all || true; pause ;;
      8)  export_snap || true; pause ;;
      9)  export_flatpak || true; pause ;;
      10)
        case "$PKG_MANAGER" in
          apt)    import_apt || true ;;
          dnf|yum) import_rpm || true ;;
          pacman) import_pacman || true ;;
          *) log_warn "Import not supported for $PKG_MANAGER" ;;
        esac
        pause
        ;;
      e|E) show_env_info; pause ;;
      0) log_info "Bye!"; exit 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

main "$@"
