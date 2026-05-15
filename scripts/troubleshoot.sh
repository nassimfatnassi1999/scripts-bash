#!/usr/bin/env bash
# scripts/troubleshoot.sh — System and network troubleshooting toolkit
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
register_cleanup

SCRIPT_NAME="System Troubleshooter"
SCRIPT_DESC="Collect diagnostics, inspect common failures, and run safe fixes"

handle_standard_args "$@"

REPORT_DIR="${REPORT_DIR:-${HOME}/troubleshoot-reports}"
REPORT_FILE="${REPORT_FILE:-${REPORT_DIR}/report-$(hostname)-$(date +'%Y%m%d_%H%M%S').txt}"

# ---------------------------------------------------------------------------
# UI / REPORT HELPERS
# ---------------------------------------------------------------------------
ensure_report_dir() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    log_info "[DRY-RUN] Would create report directory: $REPORT_DIR"
  else
    mkdir -p "$REPORT_DIR"
  fi
}

append_section() {
  local title="$1"
  shift
  {
    echo
    echo "============================================================================"
    echo "$title"
    echo "============================================================================"
    if "$@" 2>&1; then
      :
    else
      echo "[command failed: $*]"
    fi
  } >> "$REPORT_FILE"
}

run_if_available() {
  local cmd="$1"
  shift
  if command -v "$cmd" >/dev/null 2>&1; then
    "$cmd" "$@"
  else
    echo "$cmd not available"
  fi
}

# ---------------------------------------------------------------------------
# INFORMATION COLLECTION
# ---------------------------------------------------------------------------
show_system_info() {
  detect_os
  echo "Host        : $(hostname)"
  echo "User        : $(whoami) (UID: $EUID)"
  echo "Date        : $(date)"
  echo "OS          : ${OS_PRETTY_NAME}"
  echo "OS ID       : ${OS_ID}"
  echo "Version     : ${OS_VERSION_ID:-unknown}"
  echo "Architecture: ${ARCH}"
  echo "Kernel      : $(uname -a)"
  echo "Shell       : ${SHELL_NAME}"
  echo
  if [[ -f /etc/os-release ]]; then
    echo "== /etc/os-release =="
    sed -n '1,80p' /etc/os-release
  fi
}

show_cpu_memory() {
  echo "== Uptime / Load =="
  uptime || true
  echo
  echo "== CPU =="
  if command -v lscpu >/dev/null 2>&1; then
    lscpu
  else
    getconf _NPROCESSORS_ONLN 2>/dev/null || true
  fi
  echo
  echo "== Top Processes =="
  if command -v ps >/dev/null 2>&1; then
    ps -eo pid,ppid,user,stat,pcpu,pmem,comm --sort=-pcpu | head -15
  fi
  echo
  echo "== Memory =="
  run_if_available free -h
  echo
  echo "== Swap =="
  if command -v swapon >/dev/null 2>&1; then
    swapon --show || true
  else
    echo "swapon not available"
  fi
}

show_disk_info() {
  echo "== Block Devices =="
  if command -v lsblk >/dev/null 2>&1; then
    lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS,ROTA,TYPE 2>/dev/null || lsblk
  else
    echo "lsblk not available"
  fi
  echo
  echo "== Filesystem Usage =="
  df -hT 2>/dev/null || df -h
  echo
  echo "== Inode Usage =="
  df -i 2>/dev/null || true
}

show_network_info() {
  echo "== Interfaces =="
  if command -v ip >/dev/null 2>&1; then
    ip -br addr || ip addr
  elif command -v ifconfig >/dev/null 2>&1; then
    ifconfig
  else
    echo "ip/ifconfig not available"
  fi
  echo
  echo "== Routes =="
  if command -v ip >/dev/null 2>&1; then
    ip route
  else
    netstat -rn 2>/dev/null || route -n 2>/dev/null || true
  fi
  echo
  echo "== DNS =="
  [[ -f /etc/resolv.conf ]] && sed -n '1,120p' /etc/resolv.conf
  if command -v resolvectl >/dev/null 2>&1; then
    echo
    resolvectl status 2>/dev/null | sed -n '1,140p' || true
  fi
  echo
  echo "== Listening Ports =="
  if command -v ss >/dev/null 2>&1; then
    ss -tulnp 2>/dev/null || ss -tuln
  elif command -v netstat >/dev/null 2>&1; then
    netstat -tulnp 2>/dev/null || netstat -tuln
  else
    echo "ss/netstat not available"
  fi
}

show_logs_info() {
  echo "== Kernel Ring Buffer =="
  dmesg 2>/dev/null | tail -80 || echo "dmesg not available or requires privileges"
  echo
  echo "== Journal Errors =="
  if command -v journalctl >/dev/null 2>&1; then
    journalctl -b -p err..alert --no-pager 2>/dev/null | tail -160 || true
  else
    echo "journalctl not available"
  fi
  echo
  echo "== Syslog / Messages =="
  if [[ -f /var/log/syslog ]]; then
    tail -120 /var/log/syslog
  elif [[ -f /var/log/messages ]]; then
    tail -120 /var/log/messages
  elif [[ -f /var/log/system.log ]]; then
    tail -120 /var/log/system.log
  else
    echo "No known syslog file found"
  fi
}

show_service_snapshot() {
  local -a services=("NetworkManager" "systemd-resolved" "ssh" "sshd" "firewalld" "ufw" "docker" "containerd" "nginx" "apache2" "httpd" "mysql" "mariadb" "postgresql")
  local svc

  if ! systemd_available; then
    log_warn "systemd is not available on this system."
    if command -v rc-status >/dev/null 2>&1; then
      rc-status || true
    fi
    return 0
  fi

  for svc in "${services[@]}"; do
    if systemctl list-unit-files "${svc}.service" >/dev/null 2>&1; then
      echo "== ${svc} =="
      systemctl status "$svc" --no-pager -l 2>/dev/null | sed -n '1,18p' || true
      echo
    fi
  done
}

show_package_manager_info() {
  detect_package_manager || true
  echo "Package manager: ${PKG_MANAGER:-unknown}"
  echo
  case "${PKG_MANAGER:-unknown}" in
    apt)
      apt-get --version | head -1
      echo
      apt list --upgradable 2>/dev/null | sed -n '1,40p' || true
      ;;
    dnf)
      dnf --version | head -5
      echo
      dnf check-update 2>/dev/null | sed -n '1,80p' || true
      ;;
    yum)
      yum --version | head -5
      echo
      yum check-update 2>/dev/null | sed -n '1,80p' || true
      ;;
    pacman)
      pacman --version | head -2
      echo
      pacman -Qu 2>/dev/null | sed -n '1,80p' || true
      ;;
    zypper)
      zypper --version
      echo
      zypper list-updates 2>/dev/null | sed -n '1,80p' || true
      ;;
    apk)
      apk --version
      echo
      apk version -l '<' 2>/dev/null | sed -n '1,80p' || true
      ;;
    *)
      echo "No supported package manager detected."
      ;;
  esac
}

# ---------------------------------------------------------------------------
# DIAGNOSTICS
# ---------------------------------------------------------------------------
check_disk_space() {
  log_info "Checking disk usage (warning threshold: 90%)..."
  local bad=0
  local fs size used avail pct mount pct_num

  while read -r fs size used avail pct mount; do
    pct_num="${pct%\%}"
    if [[ "$pct_num" =~ ^[0-9]+$ ]] && (( pct_num >= 90 )); then
      bad=1
      log_warn "High disk usage: $mount is ${pct_num}% used (available: $avail)."
      echo "  Suggested checks:"
      echo "  - sudo du -xh '$mount' | sort -h | tail -30"
      echo "  - journalctl disk usage: journalctl --disk-usage"
      echo "  - Docker usage: docker system df"
    fi
  done < <(df -hP | awk 'NR>1 {print $1,$2,$3,$4,$5,$6}')

  [[ "$bad" -eq 0 ]] && log_ok "Disk usage looks OK."
}

check_inodes() {
  log_info "Checking inode usage (warning threshold: 90%)..."
  local bad=0
  local fs inodes iused ifree ipct mount pct_num

  while read -r fs inodes iused ifree ipct mount; do
    pct_num="${ipct%\%}"
    if [[ "$pct_num" =~ ^[0-9]+$ ]] && (( pct_num >= 90 )); then
      bad=1
      log_warn "High inode usage: $mount is ${pct_num}% used."
      echo "  Suggested checks:"
      echo "  - sudo find '$mount' -xdev -type f | wc -l"
      echo "  - inspect caches, node_modules, mail spools, and log directories"
    fi
  done < <(df -iP | awk 'NR>1 {print $1,$2,$3,$4,$5,$6}')

  [[ "$bad" -eq 0 ]] && log_ok "Inode usage looks OK."
}

check_memory_pressure() {
  log_info "Checking memory pressure..."
  if ! command -v free >/dev/null 2>&1; then
    log_warn "free command not available."
    return 0
  fi

  local mem_total mem_avail swap_total swap_used avail_pct swap_pct
  mem_total="$(free -b | awk '/Mem:/ {print $2}')"
  mem_avail="$(free -b | awk '/Mem:/ {print $7}')"
  swap_total="$(free -b | awk '/Swap:/ {print $2}')"
  swap_used="$(free -b | awk '/Swap:/ {print $3}')"

  if [[ "$mem_total" =~ ^[0-9]+$ && "$mem_total" -gt 0 ]]; then
    avail_pct=$(( mem_avail * 100 / mem_total ))
    if (( avail_pct < 10 )); then
      log_warn "Low available RAM: ${avail_pct}%."
      echo "  Suggested checks: ps aux --sort=-%mem | head"
    else
      log_ok "RAM availability looks OK: ${avail_pct}% available."
    fi
  fi

  if [[ "$swap_total" =~ ^[0-9]+$ && "$swap_total" -gt 0 ]]; then
    swap_pct=$(( swap_used * 100 / swap_total ))
    if (( swap_pct > 50 )); then
      log_warn "High swap usage: ${swap_pct}%."
    else
      log_ok "Swap usage looks OK: ${swap_pct}%."
    fi
  else
    log_info "No swap configured."
  fi
}

check_dns() {
  log_info "Checking DNS resolution..."
  if command -v getent >/dev/null 2>&1 && getent hosts github.com >/dev/null 2>&1; then
    log_ok "DNS resolves github.com."
  elif command -v nslookup >/dev/null 2>&1 && nslookup github.com >/dev/null 2>&1; then
    log_ok "DNS resolves github.com."
  else
    log_warn "DNS resolution failed."
    echo "  Suggested checks:"
    echo "  - cat /etc/resolv.conf"
    echo "  - resolvectl status"
    echo "  - restart NetworkManager or systemd-resolved if applicable"
  fi
}

check_connectivity() {
  log_info "Checking gateway and internet connectivity..."
  local gw=""

  if command -v ip >/dev/null 2>&1; then
    gw="$(ip route 2>/dev/null | awk '/default/ {print $3; exit}')"
  fi

  if [[ -z "$gw" ]]; then
    log_warn "No default gateway detected."
  elif command -v ping >/dev/null 2>&1 && ping -c 1 -W 2 "$gw" >/dev/null 2>&1; then
    log_ok "Gateway reachable: $gw"
  else
    log_warn "Gateway not reachable: $gw"
  fi

  if command -v ping >/dev/null 2>&1 && ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
    log_ok "Internet reachable by ICMP: 1.1.1.1"
  elif command -v curl >/dev/null 2>&1 && curl -fsSL --max-time 5 https://example.com >/dev/null 2>&1; then
    log_ok "Internet reachable by HTTPS."
  else
    log_warn "Internet connectivity check failed."
  fi
}

check_time_sync() {
  log_info "Checking time synchronization..."
  if command -v timedatectl >/dev/null 2>&1; then
    local synced
    synced="$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)"
    if [[ "$synced" == "yes" ]]; then
      log_ok "Time is synchronized."
    else
      log_warn "Time is not synchronized."
      echo "  Suggested fix: sudo timedatectl set-ntp true"
    fi
  else
    log_warn "timedatectl not available."
  fi
}

check_failed_services() {
  log_info "Checking failed services..."
  if systemd_available; then
    if systemctl --failed --no-pager --plain | grep -q failed; then
      systemctl --failed --no-pager
    else
      log_ok "No failed systemd units detected."
    fi
  else
    log_warn "systemd not available."
  fi
}

run_diagnostics() {
  check_disk_space
  echo
  check_inodes
  echo
  check_memory_pressure
  echo
  check_time_sync
  echo
  check_failed_services
  echo
  check_connectivity
  echo
  check_dns
  echo
  log_ok "Diagnostics completed."
}

# ---------------------------------------------------------------------------
# FIX ACTIONS
# ---------------------------------------------------------------------------
restart_service_if_present() {
  local svc="$1"
  check_sudo
  if ! systemd_available; then
    log_error "systemd is not available."
    return 1
  fi
  if ! systemctl list-unit-files "${svc}.service" >/dev/null 2>&1; then
    log_error "Service not found: $svc"
    return 1
  fi
  if ask_confirm "Restart service '$svc'?"; then
    run_cmd_sudo systemctl restart "$svc"
    log_ok "Service restarted: $svc"
  fi
}

vacuum_journal() {
  check_sudo
  require_command journalctl "journalctl is required."
  local days
  days="$(ask_input "Vacuum journal logs older than N days" "7")"
  if [[ ! "$days" =~ ^[0-9]+$ || "$days" -lt 1 ]]; then
    log_error "Invalid number of days: $days"
    return 1
  fi
  log_warn "This deletes journal entries older than ${days} days."
  if ask_confirm "Proceed with journal vacuum?"; then
    run_cmd_sudo journalctl --vacuum-time="${days}d"
    log_ok "Journal vacuum completed."
  fi
}

package_cleanup() {
  check_sudo
  detect_package_manager
  log_warn "This removes package cache and/or unused packages where supported."
  if ! ask_confirm "Proceed with package cleanup for ${PKG_MANAGER}?"; then
    log_warn "Cancelled."
    return 0
  fi

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
    pacman)
      run_cmd_sudo pacman -Sc --noconfirm
      ;;
    zypper)
      run_cmd_sudo zypper clean --all
      ;;
    apk)
      run_cmd_sudo apk cache clean
      ;;
    *)
      log_error "Unsupported package manager."
      return 1
      ;;
  esac

  log_ok "Package cleanup completed."
}

flush_dns_cache() {
  check_sudo
  if command -v resolvectl >/dev/null 2>&1; then
    run_cmd_sudo resolvectl flush-caches
    log_ok "systemd-resolved DNS cache flushed."
  elif systemd_available && systemctl list-unit-files systemd-resolved.service >/dev/null 2>&1; then
    restart_service_if_present systemd-resolved
  elif command -v nscd >/dev/null 2>&1; then
    run_cmd_sudo nscd -i hosts
    log_ok "nscd hosts cache flushed."
  else
    log_warn "No supported DNS cache service detected."
  fi
}

# ---------------------------------------------------------------------------
# REPORT
# ---------------------------------------------------------------------------
generate_full_report() {
  ensure_report_dir
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    log_info "[DRY-RUN] Would generate report: $REPORT_FILE"
    return 0
  fi

  : > "$REPORT_FILE"
  append_section "HEADER" show_system_info
  append_section "CPU / MEMORY" show_cpu_memory
  append_section "DISK" show_disk_info
  append_section "NETWORK" show_network_info
  append_section "LOGS" show_logs_info
  append_section "SERVICES" show_service_snapshot
  append_section "PACKAGE MANAGER" show_package_manager_info
  append_section "DIAGNOSTICS" run_diagnostics
  log_ok "Report written to: $REPORT_FILE"
}

show_status() {
  detect_package_manager 2>/dev/null || true
  echo
  log_info "Report file: $REPORT_FILE"
  log_info "Package manager: ${PKG_MANAGER:-unknown}"
  if systemd_available; then
    log_ok "systemd: available"
  else
    log_warn "systemd: not available"
  fi
  echo
}

# ---------------------------------------------------------------------------
# MENU
# ---------------------------------------------------------------------------
main_menu_choice() {
  menu_select "$SCRIPT_NAME" "Exit" \
    "1:Show system info" \
    "2:Show CPU / memory / swap" \
    "3:Show disk / filesystem usage" \
    "4:Show network info" \
    "5:Show recent logs" \
    "6:Show service snapshot" \
    "7:Show package manager info" \
    "8:Run diagnostics" \
    "9:Generate full report" \
    "10:Restart NetworkManager" \
    "11:Restart systemd-resolved" \
    "12:Vacuum journal logs" \
    "13:Package cleanup" \
    "14:Flush DNS cache" \
    "e:Show environment info"
}

main() {
  while true; do
    print_script_header "$SCRIPT_NAME" "$SCRIPT_DESC"
    show_status
    main_menu_choice
    echo

    case "${REPLY:-}" in
      1) show_system_info || true; pause ;;
      2) show_cpu_memory || true; pause ;;
      3) show_disk_info || true; pause ;;
      4) show_network_info || true; pause ;;
      5) show_logs_info || true; pause ;;
      6) show_service_snapshot || true; pause ;;
      7) show_package_manager_info || true; pause ;;
      8) run_diagnostics || true; pause ;;
      9) generate_full_report || true; pause ;;
      10) restart_service_if_present NetworkManager || true; pause ;;
      11) restart_service_if_present systemd-resolved || true; pause ;;
      12) vacuum_journal || true; pause ;;
      13) package_cleanup || true; pause ;;
      14) flush_dns_cache || true; pause ;;
      e|E) show_env_info; pause ;;
      0) log_info "Bye!"; exit 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

main "$@"
