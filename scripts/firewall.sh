#!/usr/bin/env bash
# scripts/firewall.sh — Firewall manager for ufw/firewalld/iptables/nftables
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
register_cleanup

SCRIPT_NAME="Firewall Manager"
SCRIPT_DESC="Inspect and manage common Linux firewall tools"

handle_standard_args "$@"

FW_TOOL="${FW_TOOL:-}"

detect_firewall() {
  if [[ -n "$FW_TOOL" ]] && command -v "$FW_TOOL" >/dev/null 2>&1; then return 0; fi
  if command -v ufw >/dev/null 2>&1; then FW_TOOL="ufw"
  elif command -v firewall-cmd >/dev/null 2>&1; then FW_TOOL="firewalld"
  elif command -v nft >/dev/null 2>&1; then FW_TOOL="nft"
  elif command -v iptables >/dev/null 2>&1; then FW_TOOL="iptables"
  else FW_TOOL=""
  fi
}

install_firewall_tools() {
  check_sudo
  detect_package_manager
  menu_select "Install Firewall Tool" "Cancel" "1:ufw" "2:firewalld" "3:nftables" "4:iptables"
  case "$REPLY" in
    1) install_package ufw ;;
    2) install_package firewalld ;;
    3) install_package nftables ;;
    4) install_package iptables ;;
    0) return 0 ;;
    *) log_warn "Invalid option."; return 1 ;;
  esac
}

select_firewall() {
  menu_select "Select Firewall Backend" "Cancel" "1:ufw" "2:firewalld" "3:nft" "4:iptables"
  case "$REPLY" in
    1) require_command ufw; FW_TOOL="ufw" ;;
    2) require_command firewall-cmd; FW_TOOL="firewalld" ;;
    3) require_command nft; FW_TOOL="nft" ;;
    4) require_command iptables; FW_TOOL="iptables" ;;
    0) return 0 ;;
    *) log_warn "Invalid option."; return 1 ;;
  esac
  log_ok "Selected firewall backend: $FW_TOOL"
}

show_firewall_status() {
  detect_firewall
  echo
  log_info "Selected backend: ${FW_TOOL:-none}"
  case "$FW_TOOL" in
    ufw) run_cmd_sudo ufw status verbose ;;
    firewalld) firewall-cmd --state 2>/dev/null || true; firewall-cmd --list-all 2>/dev/null || true ;;
    nft) run_cmd_sudo nft list ruleset ;;
    iptables) run_cmd_sudo iptables -S; run_cmd_sudo iptables -L -n -v ;;
    *) log_warn "No firewall backend detected." ;;
  esac
}

enable_firewall() {
  detect_firewall
  check_sudo
  case "$FW_TOOL" in
    ufw)
      log_warn "Enabling ufw may disconnect remote SSH sessions if SSH is not allowed."
      if ask_confirm "Allow OpenSSH before enabling ufw?"; then run_cmd_sudo ufw allow OpenSSH || run_cmd_sudo ufw allow 22/tcp; fi
      ask_confirm "Enable ufw?" && run_cmd_sudo ufw --force enable
      ;;
    firewalld)
      service_enable_start firewalld
      ;;
    nft)
      service_enable_start nftables
      ;;
    iptables)
      log_warn "iptables has no universal enable command. Rules are active when inserted."
      ;;
    *) log_error "No firewall backend selected."; return 1 ;;
  esac
}

disable_firewall() {
  detect_firewall
  check_sudo
  log_warn "Disabling firewall protection can expose this host."
  if ! ask_confirm "Disable firewall backend '${FW_TOOL:-unknown}'?"; then return 0; fi
  case "$FW_TOOL" in
    ufw) run_cmd_sudo ufw disable ;;
    firewalld) run_cmd_sudo systemctl disable --now firewalld ;;
    nft) run_cmd_sudo systemctl disable --now nftables || true ;;
    iptables) run_cmd_sudo iptables -F ;;
    *) log_error "No firewall backend selected."; return 1 ;;
  esac
}

allow_port() {
  detect_firewall
  check_sudo
  local port proto
  port="$(ask_input "Port number")"
  proto="$(ask_input "Protocol" "tcp")"
  [[ "$port" =~ ^[0-9]+$ ]] || { log_error "Invalid port."; return 1; }
  case "$FW_TOOL" in
    ufw) run_cmd_sudo ufw allow "${port}/${proto}" ;;
    firewalld)
      run_cmd_sudo firewall-cmd --permanent --add-port="${port}/${proto}"
      run_cmd_sudo firewall-cmd --reload
      ;;
    nft)
      log_info "nft direct rule will be added to inet filter input if table/chain exists."
      run_cmd_sudo nft add rule inet filter input "${proto}" dport "$port" accept
      ;;
    iptables) run_cmd_sudo iptables -A INPUT -p "$proto" --dport "$port" -j ACCEPT ;;
    *) log_error "No firewall backend selected."; return 1 ;;
  esac
}

deny_port() {
  detect_firewall
  check_sudo
  local port proto
  port="$(ask_input "Port number")"
  proto="$(ask_input "Protocol" "tcp")"
  [[ "$port" =~ ^[0-9]+$ ]] || { log_error "Invalid port."; return 1; }
  log_warn "This will block traffic to ${port}/${proto}."
  if ! ask_confirm "Proceed?"; then return 0; fi
  case "$FW_TOOL" in
    ufw) run_cmd_sudo ufw deny "${port}/${proto}" ;;
    firewalld)
      run_cmd_sudo firewall-cmd --permanent --remove-port="${port}/${proto}" || true
      run_cmd_sudo firewall-cmd --reload
      ;;
    nft) run_cmd_sudo nft add rule inet filter input "${proto}" dport "$port" drop ;;
    iptables) run_cmd_sudo iptables -A INPUT -p "$proto" --dport "$port" -j DROP ;;
    *) log_error "No firewall backend selected."; return 1 ;;
  esac
}

allow_service() {
  detect_firewall
  check_sudo
  local svc
  svc="$(ask_input "Service name (ssh/http/https/etc.)" "ssh")"
  require_not_empty "$svc" "Service"
  case "$FW_TOOL" in
    ufw) run_cmd_sudo ufw allow "$svc" ;;
    firewalld)
      run_cmd_sudo firewall-cmd --permanent --add-service="$svc"
      run_cmd_sudo firewall-cmd --reload
      ;;
    *) log_error "Service rules are only supported for ufw/firewalld."; return 1 ;;
  esac
}

main_menu_choice() {
  menu_select "$SCRIPT_NAME" "Exit" \
    "1:Show firewall status" \
    "2:Select firewall backend" \
    "3:Install firewall tools" \
    "4:Enable firewall" \
    "5:Disable firewall" \
    "6:Allow port" \
    "7:Deny port" \
    "8:Allow service" \
    "e:Show environment info"
}

main() {
  detect_firewall
  while true; do
    print_script_header "$SCRIPT_NAME" "$SCRIPT_DESC"
    log_info "Backend: ${FW_TOOL:-not detected}"
    main_menu_choice
    echo
    case "${REPLY:-}" in
      1) show_firewall_status || true; pause ;;
      2) select_firewall || true; pause ;;
      3) install_firewall_tools || true; pause ;;
      4) enable_firewall || true; pause ;;
      5) disable_firewall || true; pause ;;
      6) allow_port || true; pause ;;
      7) deny_port || true; pause ;;
      8) allow_service || true; pause ;;
      e|E) show_env_info; pause ;;
      0) log_info "Bye!"; exit 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

main "$@"
