#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# =========================
# System & Network Troubleshooter (Menu)
# Pop!_OS / Ubuntu friendly
# =========================

# -------- UI ----------
if command -v tput >/dev/null 2>&1; then
  BOLD="$(tput bold)"; RESET="$(tput sgr0)"
  RED="$(tput setaf 1)"; GREEN="$(tput setaf 2)"; YELLOW="$(tput setaf 3)"; CYAN="$(tput setaf 6)"; MAGENTA="$(tput setaf 5)"
else
  BOLD=""; RESET=""; RED=""; GREEN=""; YELLOW=""; CYAN=""; MAGENTA=""
fi

LOG()  { echo "[$(date +'%F %T')] $*"; }
OK()   { echo "${GREEN}${BOLD}[OK]${RESET} $*"; }
INFO() { echo "${CYAN}${BOLD}[i]${RESET} $*"; }
WARN() { echo "${YELLOW}${BOLD}[!]${RESET} $*"; }
ERR()  { echo "${RED}${BOLD}[X]${RESET} $*" >&2; }

pause() { read -r -p "Press Enter to continue... " _; }

need_cmd() { command -v "$1" >/dev/null 2>&1; }

require_sudo() {
  if ! need_cmd sudo; then
    ERR "sudo not installed."
    return 1
  fi
  if ! sudo -n true 2>/dev/null; then
    INFO "Sudo required (you may be prompted)."
    sudo true
  fi
}

# -------- Report output ----------
OUT_DIR="${HOME}/troubleshoot-reports"
mkdir -p "$OUT_DIR"
REPORT_FILE="${REPORT_FILE:-$OUT_DIR/report-$(hostname)-$(date +'%F_%H%M%S').txt}"

append() { # append command output to report
  {
    echo
    echo "==== $1 ===="
    shift
    if "$@" 2>&1; then :; else echo "[command failed]"; fi
  } >>"$REPORT_FILE"
}

# -------- Helpers: system readings ----------
os_info() {
  echo "Host: $(hostname)"
  echo "Date: $(date)"
  echo
  echo "== Kernel =="
  uname -a
  echo
  echo "== OS Release =="
  [[ -f /etc/os-release ]] && cat /etc/os-release || true
}

cpu_mem_info() {
  echo "== Load / CPU top =="
  if need_cmd top; then top -b -n1 | head -n 12; else echo "top not found"; fi
  echo
  echo "== Memory =="
  free -h || true
  echo
  echo "== Swap =="
  swapon --show 2>/dev/null || echo "No swap configured"
}

disk_info() {
  echo "== Block devices =="
  lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,ROTA,TYPE
  echo
  echo "== Disk usage =="
  df -hT
  echo
  echo "== Inodes usage =="
  df -i
}

network_info() {
  echo "== Interfaces =="
  ip -br addr || true
  echo
  echo "== Routes =="
  ip route || true
  echo
  echo "== DNS config =="
  if [[ -f /etc/resolv.conf ]]; then
    echo "--- /etc/resolv.conf ---"
    cat /etc/resolv.conf
  fi
  if need_cmd resolvectl; then
    echo
    echo "--- resolvectl status (summary) ---"
    resolvectl status 2>/dev/null | sed -n '1,120p' || true
  fi
  echo
  echo "== Listening ports =="
  ss -tulnp 2>/dev/null || echo "ss not available"
}

logs_info() {
  echo "== Recent journal errors (last boot) =="
  if need_cmd journalctl; then
    journalctl -b -p err..alert --no-pager | tail -n 120 || true
  else
    echo "journalctl not available"
  fi
  echo
  echo "== Syslog/messages (last 80 lines) =="
  if [[ -f /var/log/syslog ]]; then
    tail -n 80 /var/log/syslog
  elif [[ -f /var/log/messages ]]; then
    tail -n 80 /var/log/messages
  else
    echo "No syslog/messages found"
  fi
}

services_info() {
  local services=("ssh" "NetworkManager" "systemd-resolved" "ufw" "firewalld" "docker" "nginx" "apache2" "mysql" "postgresql")
  echo "== Selected service status (short) =="
  for svc in "${services[@]}"; do
    if need_cmd systemctl && systemctl list-unit-files | grep -qiE "^${svc}\.service"; then
      echo "--- $svc ---"
      systemctl --no-pager --full -l status "$svc" | head -n 12 || true
      echo
    else
      echo "--- $svc ---"
      echo "Not installed or not a systemd service."
      echo
    fi
  done
}

# -------- Diagnostics (detect common problems) ----------
# Each check prints: status + probable causes + suggested fixes
check_disk_space() {
  INFO "Checking disk space (>=90% used => warning)..."
  local bad=0
  while read -r fs size used avail pct mount; do
    pct="${pct%\%}"
    if [[ "$pct" =~ ^[0-9]+$ ]] && (( pct >= 90 )); then
      bad=1
      WARN "High disk usage: $mount is ${pct}% used (avail: $avail)."
      echo "  Possible causes: logs growing, cache, large downloads, docker images, timeshift snapshots, low disk size."
      echo "  Suggested fixes:"
      echo "    - sudo du -xh / | sort -h | tail -n 30   (or use ncdu)"
      echo "    - sudo journalctl --vacuum-time=7d"
      echo "    - sudo apt autoremove && sudo apt clean"
      echo "    - docker system prune -a (if you use docker)"
    fi
  done < <(df -hP | awk 'NR>1{print $1,$2,$3,$4,$5,$6}')
  (( bad == 0 )) && OK "Disk usage looks OK (<90%)."
}

check_inodes() {
  INFO "Checking inode usage (>=90% => warning)..."
  local bad=0
  while read -r fs inodes iused ifree ipct mount; do
    ipct="${ipct%\%}"
    if [[ "$ipct" =~ ^[0-9]+$ ]] && (( ipct >= 90 )); then
      bad=1
      WARN "High inode usage: $mount is ${ipct}% inodes used."
      echo "  Possible causes: millions of small files (node_modules, caches, mail spools, logs)."
      echo "  Suggested fixes:"
      echo "    - sudo find $mount -xdev -type f | wc -l"
      echo "    - locate big small-file directories (e.g., ~/.cache, node_modules) and clean."
    fi
  done < <(df -iP | awk 'NR>1{print $1,$2,$3,$4,$5,$6}')
  (( bad == 0 )) && OK "Inode usage looks OK (<90%)."
}

check_memory() {
  INFO "Checking memory pressure..."
  if ! need_cmd free; then WARN "free not found"; return 0; fi
  local mem_total mem_avail swap_total swap_used
  mem_total=$(free -b | awk '/Mem:/ {print $2}')
  mem_avail=$(free -b | awk '/Mem:/ {print $7}')
  swap_total=$(free -b | awk '/Swap:/ {print $2}')
  swap_used=$(free -b | awk '/Swap:/ {print $3}')

  if [[ "$mem_total" -gt 0 ]]; then
    local avail_pct=$(( mem_avail * 100 / mem_total ))
    if (( avail_pct < 10 )); then
      WARN "Low available RAM (~${avail_pct}% available)."
      echo "  Possible causes: heavy apps (browser), VM/containers, memory leak."
      echo "  Suggested fixes:"
      echo "    - check top/htop: sort by %MEM"
      echo "    - restart the offending app/service"
      echo "    - add swap or more RAM"
    else
      OK "RAM availability looks OK (~${avail_pct}% available)."
    fi
  fi

  if [[ "$swap_total" -gt 0 ]]; then
    local swap_pct=$(( swap_used * 100 / swap_total ))
    if (( swap_pct > 50 )); then
      WARN "Swap usage is high (${swap_pct}%)."
      echo "  Possible causes: RAM pressure; system will feel slow."
      echo "  Suggested fixes: close heavy apps, reboot, add RAM, increase swap."
    fi
  else
    INFO "No swap configured."
  fi
}

check_dns() {
  INFO "Checking DNS resolution..."
  if need_cmd getent && getent hosts github.com >/dev/null 2>&1; then
    OK "DNS resolution OK (github.com resolves)."
  else
    WARN "DNS resolution FAILED."
    echo "  Possible causes: wrong DNS servers, systemd-resolved issues, VPN, captive portal."
    echo "  Suggested fixes:"
    echo "    - check /etc/resolv.conf"
    echo "    - restart resolver: sudo systemctl restart systemd-resolved (if used)"
    echo "    - on Pop!_OS: ensure NetworkManager is managing DNS"
    echo "    - try: resolvectl query github.com"
  fi
}

check_gateway_internet() {
  INFO "Checking gateway + internet connectivity..."
  local gw
  gw="$(ip route 2>/dev/null | awk '/default/ {print $3; exit}')"
  if [[ -z "${gw:-}" ]]; then
    WARN "No default gateway found."
    echo "  Possible causes: Wi-Fi not connected, DHCP failed, static config missing."
    echo "  Suggested fixes:"
    echo "    - nmcli dev status"
    echo "    - nmcli con show --active"
    echo "    - restart network: sudo systemctl restart NetworkManager"
    return 0
  fi

  if need_cmd ping && ping -c 1 -W 1 "$gw" >/dev/null 2>&1; then
    OK "Gateway reachable: $gw"
  else
    WARN "Gateway NOT reachable: $gw"
    echo "  Possible causes: Wi-Fi/router issue, wrong IP, firewall, link down."
    echo "  Suggested fixes:"
    echo "    - ip link"
    echo "    - nmcli dev wifi (if wifi)"
    echo "    - reboot router or reconnect"
    return 0
  fi

  # Internet check: ICMP to 1.1.1.1
  if need_cmd ping && ping -c 1 -W 1 1.1.1.1 >/dev/null 2>&1; then
    OK "Internet reachable (ping 1.1.1.1)."
  else
    WARN "Internet ping to 1.1.1.1 failed."
    echo "  Possible causes: ISP issue, firewall blocking ICMP, routing issue, VPN."
    echo "  Suggested fixes: test HTTP: curl -I https://1.1.1.1 or https://example.com"
  fi
}

check_time_sync() {
  INFO "Checking time sync (TLS problems often due to wrong clock)..."
  if need_cmd timedatectl; then
    local synced
    synced="$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)"
    if [[ "$synced" == "yes" ]]; then
      OK "Time is synchronized (NTP)."
    else
      WARN "Time NOT synchronized."
      echo "  Possible causes: NTP disabled, blocked NTP, wrong timezone."
      echo "  Suggested fixes:"
      echo "    - sudo timedatectl set-ntp true"
      echo "    - check timezone: timedatectl"
    fi
  else
    WARN "timedatectl not available."
  fi
}

check_services_quick() {
  INFO "Checking common critical services..."
  if ! need_cmd systemctl; then WARN "systemctl not available"; return 0; fi

  local targets=("NetworkManager" "systemd-resolved")
  for s in "${targets[@]}"; do
    if systemctl list-unit-files | grep -qiE "^${s}\.service"; then
      if systemctl is-active --quiet "$s"; then
        OK "Service active: $s"
      else
        WARN "Service NOT active: $s"
        echo "  Suggested fix: sudo systemctl restart $s"
      fi
    fi
  done
}

# -------- Fix actions (interactive) ----------
fix_restart_networkmanager() {
  require_sudo
  INFO "Restarting NetworkManager..."
  sudo systemctl restart NetworkManager
  OK "NetworkManager restarted."
}

fix_restart_resolved() {
  require_sudo
  INFO "Restarting systemd-resolved..."
  sudo systemctl restart systemd-resolved
  OK "systemd-resolved restarted."
}

fix_vacuum_journal() {
  require_sudo
  read -r -p "Vacuum journal logs older than how many days? (e.g., 7): " days
  if [[ -z "${days:-}" || ! "$days" =~ ^[0-9]+$ ]]; then
    ERR "Invalid number."
    return 1
  fi
  INFO "Vacuuming journal older than ${days}d..."
  sudo journalctl --vacuum-time="${days}d"
  OK "Journal vacuum done."
}

fix_apt_cleanup() {
  require_sudo
  INFO "Running apt cleanup (autoremove + clean)..."
  sudo apt autoremove -y
  sudo apt clean
  OK "APT cleanup done."
}

# -------- Collection ----------
generate_full_report() {
  INFO "Generating report: $REPORT_FILE"
  : >"$REPORT_FILE"

  append "HEADER" bash -lc 'echo "Host: $(hostname)"; echo "Date: $(date)"; echo "User: $(whoami)"; echo'
  append "SYSTEM INFO" bash -lc "$(declare -f os_info); os_info"
  append "CPU/MEM" bash -lc "$(declare -f cpu_mem_info); cpu_mem_info"
  append "DISK" bash -lc "$(declare -f disk_info); disk_info"
  append "NETWORK" bash -lc "$(declare -f network_info); network_info"
  append "LOGS" bash -lc "$(declare -f logs_info); logs_info"
  append "SERVICES" bash -lc "$(declare -f services_info); services_info"

  OK "Report written to: $REPORT_FILE"
}

run_diagnostics() {
  echo "${MAGENTA}${BOLD}== Diagnostics ==${RESET}"
  check_disk_space
  echo
  check_inodes
  echo
  check_memory
  echo
  check_time_sync
  echo
  check_services_quick
  echo
  check_gateway_internet
  echo
  check_dns
  echo
  OK "Diagnostics completed."
}

# -------- Menu ----------
header() {
  clear || true
  echo "${BOLD}=========================================${RESET}"
  echo "${BOLD}   System & Network Troubleshooter Menu  ${RESET}"
  echo "${BOLD}=========================================${RESET}"
  echo "Host: $(hostname) | Date: $(date +'%F %T')"
  echo "Report file: $REPORT_FILE"
  echo
}

menu() {
  echo "${BOLD}1) Show System Info${RESET}"
  echo "${BOLD}2) Show CPU/Memory/Swap${RESET}"
  echo "${BOLD}3) Show Disk/Filesystem Usage${RESET}"
  echo "${BOLD}4) Show Network Info (IP/routes/DNS/ports)${RESET}"
  echo "${BOLD}5) Show Recent Logs (errors)${RESET}"
  echo "${BOLD}6) Run Diagnostics (detect common problems + fixes suggestions)${RESET}"
  echo "${BOLD}7) Generate Full Report to file${RESET}"
  echo "${BOLD}8) Fix: Restart NetworkManager${RESET}"
  echo "${BOLD}9) Fix: Restart systemd-resolved${RESET}"
  echo "${BOLD}10) Fix: Vacuum journal logs${RESET}"
  echo "${BOLD}11) Fix: apt cleanup (autoremove + clean)${RESET}"
  echo "${BOLD}0) Exit${RESET}"
  echo
}

main() {
  while true; do
    header
    menu
    read -r -p "Choose an option: " c
    echo
    case "${c:-}" in
      1) os_info; pause ;;
      2) cpu_mem_info; pause ;;
      3) disk_info; pause ;;
      4) network_info; pause ;;
      5) logs_info; pause ;;
      6) run_diagnostics; pause ;;
      7) generate_full_report; pause ;;
      8) fix_restart_networkmanager; pause ;;
      9) fix_restart_resolved; pause ;;
      10) fix_vacuum_journal; pause ;;
      11) fix_apt_cleanup; pause ;;
      0) INFO "Bye."; exit 0 ;;
      *) WARN "Invalid option."; pause ;;
    esac
  done
}

main