#!/usr/bin/env bash
# scripts/monitoring.sh — Monitoring and observability helper
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
register_cleanup

SCRIPT_NAME="Monitoring Manager"
SCRIPT_DESC="Install and run common monitoring and observability tools"

handle_standard_args "$@"

install_monitoring_tools() {
  check_sudo
  detect_package_manager
  case "$PKG_MANAGER" in
    apt) run_cmd_sudo apt-get update -y; run_cmd_sudo apt-get install -y htop iotop iftop sysstat lsof procps net-tools curl ;;
    dnf|yum) run_cmd_sudo "$PKG_MANAGER" install -y htop iotop iftop sysstat lsof procps-ng net-tools curl ;;
    pacman) run_cmd_sudo pacman -S --noconfirm htop iotop iftop sysstat lsof procps-ng net-tools curl ;;
    zypper) run_cmd_sudo zypper install -y htop iotop iftop sysstat lsof procps net-tools curl ;;
    apk) run_cmd_sudo apk add htop iotop iftop sysstat lsof procps net-tools curl ;;
    *) log_error "Unsupported package manager."; return 1 ;;
  esac
}

system_snapshot() {
  log_info "Uptime and load"
  uptime || true
  echo
  log_info "CPU / memory"
  top -b -n1 2>/dev/null | head -20 || ps aux --sort=-%cpu | head -15
  echo
  free -h 2>/dev/null || true
  echo
  log_info "Disk usage"
  df -hT 2>/dev/null || df -h
}

process_monitor() {
  if command -v htop >/dev/null 2>&1; then htop
  elif command -v top >/dev/null 2>&1; then top
  else ps aux --sort=-%cpu | head -30
  fi
}

io_monitor() {
  if command -v iotop >/dev/null 2>&1; then
    check_sudo
    run_cmd_sudo iotop
  elif command -v iostat >/dev/null 2>&1; then
    iostat -xz 1 5
  else
    log_warn "Install iotop or sysstat for IO monitoring."
  fi
}

network_monitor() {
  if command -v iftop >/dev/null 2>&1; then
    check_sudo
    run_cmd_sudo iftop
  elif command -v ss >/dev/null 2>&1; then
    ss -tupn
  else
    netstat -tupn 2>/dev/null || true
  fi
}

show_open_files() {
  require_command lsof
  local filter
  filter="$(ask_input "Filter by process/user/path (empty for top output)" "")"
  if [[ -n "$filter" ]]; then
    lsof 2>/dev/null | grep -i -- "$filter" | head -100 || true
  else
    lsof 2>/dev/null | head -100 || true
  fi
}

watch_command() {
  require_command watch
  local cmd
  cmd="$(ask_input "Command to watch" "df -h")"
  require_not_empty "$cmd" "Command"
  log_info "Press Ctrl+C to stop."
  watch -n 2 "$cmd"
}

enable_sysstat() {
  check_sudo
  detect_package_manager
  if ! command -v sar >/dev/null 2>&1; then
    log_warn "sysstat is not installed."
    if ask_confirm "Install monitoring tools now?"; then install_monitoring_tools; fi
  fi
  if systemd_available; then
    run_cmd_sudo systemctl enable --now sysstat 2>/dev/null || true
    run_cmd_sudo systemctl enable --now sysstat-collect.timer 2>/dev/null || true
  fi
  log_ok "sysstat enable step completed."
}

view_sysstat() {
  if command -v sar >/dev/null 2>&1; then
    sar -u 1 5
    echo
    sar -r 1 5
    echo
    sar -d 1 3 2>/dev/null || true
  else
    log_warn "sar not installed."
  fi
}

main_menu_choice() {
  menu_select "$SCRIPT_NAME" "Exit" \
    "1:Install monitoring tools" \
    "2:System snapshot" \
    "3:Process monitor" \
    "4:IO monitor" \
    "5:Network monitor" \
    "6:Show open files" \
    "7:Watch command" \
    "8:Enable sysstat collection" \
    "9:View sysstat samples" \
    "e:Show environment info"
}

main() {
  while true; do
    print_script_header "$SCRIPT_NAME" "$SCRIPT_DESC"
    main_menu_choice
    echo
    case "${REPLY:-}" in
      1) install_monitoring_tools || true; pause ;;
      2) system_snapshot || true; pause ;;
      3) process_monitor || true; pause ;;
      4) io_monitor || true; pause ;;
      5) network_monitor || true; pause ;;
      6) show_open_files || true; pause ;;
      7) watch_command || true; pause ;;
      8) enable_sysstat || true; pause ;;
      9) view_sysstat || true; pause ;;
      e|E) show_env_info; pause ;;
      0) log_info "Bye!"; exit 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

main "$@"
