#!/usr/bin/env bash
# scripts/service-manager.sh — Service manager for systemd/OpenRC/SysV
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
register_cleanup

SCRIPT_NAME="Service Manager"
SCRIPT_DESC="Inspect, start, stop, restart, enable and disable services"

handle_standard_args "$@"

service_backend() {
  if command -v systemctl >/dev/null 2>&1; then echo "systemd"
  elif command -v rc-service >/dev/null 2>&1; then echo "openrc"
  elif command -v service >/dev/null 2>&1; then echo "sysv"
  else echo "unknown"
  fi
}

service_name_input() {
  local svc
  svc="$(ask_input "Service name")"
  require_not_empty "$svc" "Service name"
  printf '%s' "$svc"
}

list_services() {
  case "$(service_backend)" in
    systemd) systemctl list-units --type=service --all --no-pager ;;
    openrc) rc-status --all ;;
    sysv) service --status-all 2>&1 || true ;;
    *) log_error "No supported service manager found."; return 1 ;;
  esac
}

list_failed_services() {
  case "$(service_backend)" in
    systemd) systemctl --failed --no-pager ;;
    openrc) rc-status --crashed 2>/dev/null || rc-status --all ;;
    sysv) log_warn "Failed service listing is not supported for SysV."; ;;
    *) log_error "No supported service manager found."; return 1 ;;
  esac
}

service_action() {
  local action="$1"
  local svc
  svc="$(service_name_input)"
  check_sudo || return 1
  case "$(service_backend)" in
    systemd)
      case "$action" in
        start|stop|restart|reload|status) run_cmd_sudo systemctl "$action" "$svc" ;;
        enable) run_cmd_sudo systemctl enable "$svc" ;;
        disable) run_cmd_sudo systemctl disable "$svc" ;;
      esac
      ;;
    openrc)
      case "$action" in
        start|stop|restart|reload|status) run_cmd_sudo rc-service "$svc" "$action" ;;
        enable) run_cmd_sudo rc-update add "$svc" default ;;
        disable) run_cmd_sudo rc-update del "$svc" default ;;
      esac
      ;;
    sysv)
      case "$action" in
        start|stop|restart|reload|status) run_cmd_sudo service "$svc" "$action" ;;
        enable|disable) log_error "Enable/disable is not portable for SysV in this script."; return 1 ;;
      esac
      ;;
    *) log_error "No supported service manager found."; return 1 ;;
  esac
}

show_service_logs() {
  local svc lines
  svc="$(service_name_input)"
  lines="$(ask_input "Number of log lines" "120")"
  if [[ ! "$lines" =~ ^[0-9]+$ ]]; then lines="120"; fi
  if command -v journalctl >/dev/null 2>&1; then
    journalctl -u "$svc" -n "$lines" --no-pager
  else
    log_warn "journalctl not available."
  fi
}

show_status() {
  echo
  log_info "Backend: $(service_backend)"
  echo
}

main_menu_choice() {
  menu_select "$SCRIPT_NAME" "Exit" \
    "1:List services" \
    "2:List failed services" \
    "3:Service status" \
    "4:Start service" \
    "5:Stop service" \
    "6:Restart service" \
    "7:Reload service" \
    "8:Enable service" \
    "9:Disable service" \
    "10:Show service logs" \
    "e:Show environment info"
}

main() {
  while true; do
    print_script_header "$SCRIPT_NAME" "$SCRIPT_DESC"
    show_status
    main_menu_choice
    echo
    case "${REPLY:-}" in
      1) list_services || true; pause ;;
      2) list_failed_services || true; pause ;;
      3) service_action status || true; pause ;;
      4) service_action start || true; pause ;;
      5) service_action stop || true; pause ;;
      6) service_action restart || true; pause ;;
      7) service_action reload || true; pause ;;
      8) service_action enable || true; pause ;;
      9) service_action disable || true; pause ;;
      10) show_service_logs || true; pause ;;
      e|E) show_env_info; pause ;;
      0) log_info "Bye!"; exit 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

main "$@"
