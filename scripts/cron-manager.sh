#!/usr/bin/env bash
# scripts/cron-manager.sh — Cron and timer management
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
register_cleanup

SCRIPT_NAME="Cron Manager"
SCRIPT_DESC="View, edit, install and validate cron jobs"

handle_standard_args "$@"

install_cron() {
  check_sudo || return 1
  detect_package_manager || return 1
  case "$PKG_MANAGER" in
    apt) run_cmd_sudo apt-get update -y; run_cmd_sudo apt-get install -y cron ;;
    dnf|yum) run_cmd_sudo "$PKG_MANAGER" install -y cronie ;;
    pacman) run_cmd_sudo pacman -S --noconfirm cronie ;;
    zypper) run_cmd_sudo zypper install -y cron ;;
    apk) run_cmd_sudo apk add cronie ;;
    *) log_error "Unsupported package manager."; return 1 ;;
  esac
}

cron_service_name() {
  if systemctl list-unit-files cron.service >/dev/null 2>&1; then echo "cron"
  elif systemctl list-unit-files crond.service >/dev/null 2>&1; then echo "crond"
  else echo "cron"
  fi
}

enable_cron_service() {
  check_sudo || return 1
  if systemd_available; then
    service_enable_start "$(cron_service_name)"
  elif command -v rc-update >/dev/null 2>&1; then
    run_cmd_sudo rc-update add crond default
    run_cmd_sudo rc-service crond start
  else
    log_warn "No supported service manager found."
  fi
}

list_user_crontab() {
  crontab -l 2>/dev/null || log_warn "No crontab for current user."
}

edit_user_crontab() {
  require_command crontab
  crontab -e
}

backup_user_crontab() {
  local out="${HOME}/crontab-backup-$(date +'%Y%m%d_%H%M%S').txt"
  if crontab -l > "$out" 2>/dev/null; then
    log_ok "Crontab backed up: $out"
  else
    log_warn "No crontab to back up."
    rm -f "$out"
  fi
}

install_job() {
  require_command crontab
  local schedule command tmp
  schedule="$(ask_input "Cron schedule" "0 2 * * *")"
  command="$(ask_input "Command")"
  require_not_empty "$schedule" "Schedule"
  require_not_empty "$command" "Command"
  tmp="$(make_tmpfile)"
  crontab -l > "$tmp" 2>/dev/null || true
  printf '%s %s\n' "$schedule" "$command" >> "$tmp"
  echo
  log_info "New crontab preview:"
  cat "$tmp"
  if ask_confirm "Install this crontab?"; then
    run_cmd crontab "$tmp"
    log_ok "Cron job installed."
  fi
}

remove_matching_jobs() {
  require_command crontab
  local pattern tmp
  pattern="$(ask_input "Pattern to remove from crontab")"
  require_not_empty "$pattern" "Pattern"
  tmp="$(make_tmpfile)"
  crontab -l > "$tmp" 2>/dev/null || { log_warn "No crontab."; return 0; }
  log_warn "Lines matching '$pattern':"
  grep -n -- "$pattern" "$tmp" || true
  if ask_confirm "Remove matching lines?"; then
    grep -v -- "$pattern" "$tmp" | crontab -
    log_ok "Matching jobs removed."
  fi
}

list_system_cron() {
  log_info "/etc/crontab"
  [[ -f /etc/crontab ]] && sed -n '1,160p' /etc/crontab || true
  echo
  log_info "/etc/cron.d"
  ls -la /etc/cron.d 2>/dev/null || true
  echo
  log_info "Timers"
  systemd_available && systemctl list-timers --all --no-pager || true
}

validate_schedule() {
  local schedule
  schedule="$(ask_input "Cron schedule to validate" "*/5 * * * *")"
  local fields
  fields="$(awk '{print NF}' <<< "$schedule")"
  if [[ "$fields" -eq 5 ]]; then
    log_ok "Cron schedule has 5 fields."
  else
    log_warn "Cron schedule should usually have 5 fields; found $fields."
  fi
  echo "Minute Hour DayOfMonth Month DayOfWeek"
}

main_menu_choice() {
  menu_select "$SCRIPT_NAME" "Exit" \
    "1:Install cron" \
    "2:Enable/start cron service" \
    "3:List user crontab" \
    "4:Edit user crontab" \
    "5:Backup user crontab" \
    "6:Install new cron job" \
    "7:Remove matching cron jobs" \
    "8:List system cron/timers" \
    "9:Validate schedule shape" \
    "e:Show environment info"
}

main() {
  while true; do
    print_script_header "$SCRIPT_NAME" "$SCRIPT_DESC"
    main_menu_choice
    echo
    case "${REPLY:-}" in
      1) install_cron || true; pause ;;
      2) enable_cron_service || true; pause ;;
      3) list_user_crontab || true; pause ;;
      4) edit_user_crontab || true; pause ;;
      5) backup_user_crontab || true; pause ;;
      6) install_job || true; pause ;;
      7) remove_matching_jobs || true; pause ;;
      8) list_system_cron || true; pause ;;
      9) validate_schedule || true; pause ;;
      e|E) show_env_info; pause ;;
      0) log_info "Bye!"; exit 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

main "$@"
