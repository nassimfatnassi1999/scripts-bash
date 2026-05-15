#!/usr/bin/env bash
# scripts/system-update.sh — Cross-distro system update and maintenance
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
register_cleanup

SCRIPT_NAME="System Update Manager"
SCRIPT_DESC="Update packages, clean caches, inspect reboot status"

handle_standard_args "$@"

pkg_update_index() {
  check_sudo
  detect_package_manager
  case "$PKG_MANAGER" in
    apt) run_cmd_sudo apt-get update -y ;;
    dnf) run_cmd_sudo dnf check-update || true ;;
    yum) run_cmd_sudo yum check-update || true ;;
    pacman) run_cmd_sudo pacman -Sy ;;
    zypper) run_cmd_sudo zypper refresh ;;
    apk) run_cmd_sudo apk update ;;
    *) log_error "Unsupported package manager."; return 1 ;;
  esac
}

pkg_upgrade() {
  check_sudo
  detect_package_manager
  log_warn "This will upgrade installed packages on this system."
  [[ "${DRY_RUN:-0}" == "1" ]] && log_info "Dry-run mode is enabled."
  if ! ask_confirm "Proceed with package upgrade?"; then log_warn "Cancelled."; return 0; fi
  case "$PKG_MANAGER" in
    apt)
      run_cmd_sudo apt-get update -y
      run_cmd_sudo apt-get upgrade -y
      ;;
    dnf) run_cmd_sudo dnf upgrade -y ;;
    yum) run_cmd_sudo yum update -y ;;
    pacman) run_cmd_sudo pacman -Syu --noconfirm ;;
    zypper) run_cmd_sudo zypper update -y ;;
    apk) run_cmd_sudo apk upgrade ;;
    *) log_error "Unsupported package manager."; return 1 ;;
  esac
  log_ok "System upgrade completed."
}

pkg_full_upgrade() {
  check_sudo
  detect_package_manager
  log_warn "Full upgrade may install/remove packages to satisfy dependencies."
  if ! ask_confirm "Proceed with full upgrade?"; then log_warn "Cancelled."; return 0; fi
  case "$PKG_MANAGER" in
    apt)
      run_cmd_sudo apt-get update -y
      run_cmd_sudo apt-get dist-upgrade -y
      ;;
    dnf) run_cmd_sudo dnf distro-sync -y ;;
    yum) run_cmd_sudo yum update -y ;;
    pacman) run_cmd_sudo pacman -Syu --noconfirm ;;
    zypper) run_cmd_sudo zypper dup -y ;;
    apk) run_cmd_sudo apk upgrade --available ;;
    *) log_error "Unsupported package manager."; return 1 ;;
  esac
  log_ok "Full upgrade completed."
}

list_updates() {
  detect_package_manager
  case "$PKG_MANAGER" in
    apt)
      run_cmd_sudo apt-get update -y
      apt list --upgradable 2>/dev/null || true
      ;;
    dnf) dnf check-update || true ;;
    yum) yum check-update || true ;;
    pacman) pacman -Qu || true ;;
    zypper) zypper list-updates || true ;;
    apk)
      run_cmd_sudo apk update
      apk version -l '<' || true
      ;;
    *) log_error "Unsupported package manager."; return 1 ;;
  esac
}

cleanup_packages() {
  check_sudo
  detect_package_manager
  log_warn "This removes package caches and unused dependencies where supported."
  if ! ask_confirm "Proceed with cleanup?"; then log_warn "Cancelled."; return 0; fi
  case "$PKG_MANAGER" in
    apt)
      run_cmd_sudo apt-get autoremove -y
      run_cmd_sudo apt-get autoclean -y
      run_cmd_sudo apt-get clean
      ;;
    dnf)
      run_cmd_sudo dnf autoremove -y || true
      run_cmd_sudo dnf clean all
      ;;
    yum)
      run_cmd_sudo yum autoremove -y || true
      run_cmd_sudo yum clean all
      ;;
    pacman) run_cmd_sudo pacman -Sc --noconfirm ;;
    zypper) run_cmd_sudo zypper clean --all ;;
    apk) run_cmd_sudo apk cache clean ;;
    *) log_error "Unsupported package manager."; return 1 ;;
  esac
  log_ok "Cleanup completed."
}

repair_package_db() {
  check_sudo
  detect_package_manager
  log_warn "This attempts package database or dependency repair."
  if ! ask_confirm "Proceed with repair for ${PKG_MANAGER}?"; then log_warn "Cancelled."; return 0; fi
  case "$PKG_MANAGER" in
    apt)
      run_cmd_sudo dpkg --configure -a
      run_cmd_sudo apt-get install -f -y
      ;;
    dnf) run_cmd_sudo dnf check || true ;;
    yum) run_cmd_sudo yum check || true ;;
    pacman)
      run_cmd_sudo pacman -Dk || true
      run_cmd_sudo pacman -Syy
      ;;
    zypper) run_cmd_sudo zypper verify -y ;;
    apk) run_cmd_sudo apk fix ;;
    *) log_error "Unsupported package manager."; return 1 ;;
  esac
}

show_reboot_status() {
  echo
  if [[ -f /var/run/reboot-required ]]; then
    log_warn "Reboot required."
    [[ -f /var/run/reboot-required.pkgs ]] && cat /var/run/reboot-required.pkgs
  elif command -v needs-restarting >/dev/null 2>&1; then
    if needs-restarting -r >/dev/null 2>&1; then log_ok "No reboot required."; else log_warn "Reboot may be required."; fi
  elif command -v zypper >/dev/null 2>&1; then
    zypper ps -s || true
  else
    log_info "No distro-specific reboot marker found."
  fi
}

show_kernel_info() {
  log_info "Running kernel: $(uname -r)"
  echo
  case "$(detect_package_manager >/dev/null 2>&1; echo "$PKG_MANAGER")" in
    apt) dpkg -l 'linux-image*' 2>/dev/null | awk '/^ii/ {print $2,$3}' | tail -10 || true ;;
    dnf|yum|zypper) rpm -qa kernel\* 2>/dev/null | sort | tail -15 || true ;;
    pacman) pacman -Q linux linux-lts 2>/dev/null || true ;;
    apk) apk info | grep -E '^linux-' || true ;;
  esac
}

show_status() {
  detect_package_manager 2>/dev/null || true
  echo
  log_info "Package manager: ${PKG_MANAGER:-unknown}"
  log_info "Dry-run: ${DRY_RUN:-0}"
  show_reboot_status
  echo
}

main_menu_choice() {
  menu_select "$SCRIPT_NAME" "Exit" \
    "1:Update package index" \
    "2:List available updates" \
    "3:Upgrade packages" \
    "4:Full upgrade / distro sync" \
    "5:Clean package cache" \
    "6:Repair package database" \
    "7:Show reboot status" \
    "8:Show kernel info" \
    "e:Show environment info"
}

main() {
  while true; do
    print_script_header "$SCRIPT_NAME" "$SCRIPT_DESC"
    show_status
    main_menu_choice
    echo
    case "${REPLY:-}" in
      1) pkg_update_index || true; pause ;;
      2) list_updates || true; pause ;;
      3) pkg_upgrade || true; pause ;;
      4) pkg_full_upgrade || true; pause ;;
      5) cleanup_packages || true; pause ;;
      6) repair_package_db || true; pause ;;
      7) show_reboot_status || true; pause ;;
      8) show_kernel_info || true; pause ;;
      e|E) show_env_info; pause ;;
      0) log_info "Bye!"; exit 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

main "$@"
