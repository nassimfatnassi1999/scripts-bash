#!/usr/bin/env bash
# scripts/network-tools.sh — Network diagnostics and tools
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
register_cleanup

SCRIPT_NAME="Network Tools"
SCRIPT_DESC="Install tools and run network diagnostics"

handle_standard_args "$@"

install_network_tools() {
  detect_package_manager || return 1
  case "$PKG_MANAGER" in
    apt) check_sudo || return 1; run_cmd_sudo apt-get update -y; run_cmd_sudo apt-get install -y iproute2 iputils-ping dnsutils traceroute mtr-tiny net-tools curl wget nmap tcpdump ;;
    dnf|yum) check_sudo || return 1; run_cmd_sudo "$PKG_MANAGER" install -y iproute iputils bind-utils traceroute mtr net-tools curl wget nmap tcpdump ;;
    pacman) check_sudo || return 1; run_cmd_sudo pacman -S --noconfirm iproute2 iputils bind traceroute mtr net-tools curl wget nmap tcpdump ;;
    zypper) check_sudo || return 1; run_cmd_sudo zypper install -y iproute2 iputils bind-utils traceroute mtr net-tools curl wget nmap tcpdump ;;
    apk) check_sudo || return 1; run_cmd_sudo apk add iproute2 iputils bind-tools traceroute mtr net-tools curl wget nmap tcpdump ;;
    brew) run_cmd brew install bind curl wget nmap tcpdump traceroute mtr net-tools ;;
    *) log_error "Unsupported package manager."; return 1 ;;
  esac
}

show_interfaces() {
  ip -br addr 2>/dev/null || ifconfig 2>/dev/null || true
  echo
  ip route 2>/dev/null || route -n 2>/dev/null || true
}

dns_lookup() {
  local host
  host="$(ask_input "Host to resolve" "github.com")"
  require_not_empty "$host" "Host"
  if command -v dig >/dev/null 2>&1; then dig "$host"
  elif command -v nslookup >/dev/null 2>&1; then nslookup "$host"
  else getent hosts "$host" || true
  fi
}

ping_host() {
  local host count
  host="$(ask_input "Host to ping" "1.1.1.1")"
  count="$(ask_input "Count" "4")"
  require_command ping
  run_cmd ping -c "$count" "$host"
}

trace_host() {
  local host
  host="$(ask_input "Host to trace" "github.com")"
  if command -v mtr >/dev/null 2>&1; then run_cmd mtr -rw "$host"
  elif command -v traceroute >/dev/null 2>&1; then run_cmd traceroute "$host"
  else log_error "Install mtr or traceroute first."; return 1
  fi
}

scan_ports() {
  local host ports
  host="$(ask_input "Host to scan" "127.0.0.1")"
  ports="$(ask_input "Ports" "22,80,443")"
  require_command nmap
  log_warn "Only scan systems you own or are authorized to test."
  if ask_confirm "Run nmap scan?"; then
    run_cmd nmap -Pn -p "$ports" "$host"
  fi
}

list_listeners() {
  if command -v ss >/dev/null 2>&1; then ss -tulnp
  else netstat -tulnp 2>/dev/null || true
  fi
}

capture_packets() {
  require_command tcpdump
  check_sudo || return 1
  local iface count file
  iface="$(ask_input "Interface" "any")"
  count="$(ask_input "Packet count" "100")"
  file="$(ask_input "Output pcap file (empty for stdout)" "")"
  log_warn "Packet capture may include sensitive traffic."
  if ! ask_confirm "Start tcpdump?"; then return 0; fi
  if [[ -n "$file" ]]; then
    run_cmd_sudo tcpdump -i "$iface" -c "$count" -w "$file"
  else
    run_cmd_sudo tcpdump -i "$iface" -c "$count"
  fi
}

main_menu_choice() {
  menu_select "$SCRIPT_NAME" "Exit" \
    "1:Install network tools" \
    "2:Show interfaces and routes" \
    "3:DNS lookup" \
    "4:Ping host" \
    "5:Traceroute/MTR" \
    "6:Scan ports with nmap" \
    "7:List listening ports" \
    "8:Capture packets with tcpdump" \
    "e:Show environment info"
}

main() {
  while true; do
    print_script_header "$SCRIPT_NAME" "$SCRIPT_DESC"
    main_menu_choice
    echo
    case "${REPLY:-}" in
      1) install_network_tools || true; pause ;;
      2) show_interfaces || true; pause ;;
      3) dns_lookup || true; pause ;;
      4) ping_host || true; pause ;;
      5) trace_host || true; pause ;;
      6) scan_ports || true; pause ;;
      7) list_listeners || true; pause ;;
      8) capture_packets || true; pause ;;
      e|E) show_env_info; pause ;;
      0) log_info "Bye!"; exit 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

main "$@"
