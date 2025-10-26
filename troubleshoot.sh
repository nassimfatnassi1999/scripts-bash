#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

LOG() { echo -e "[$(date +'%F %T')] $*"; }
ERR() { echo -e "[$(date +'%F %T')] ERROR: $*" >&2; }

# --- Header ---
echo "=============================="
echo "   System Troubleshooting     "
echo "=============================="
echo "Host: $(hostname)"
echo "Date: $(date)"
echo ""

# --- System info ---
echo "== System Info =="
uname -a
echo ""
echo "== OS Info =="
if [[ -f /etc/os-release ]]; then
  cat /etc/os-release
fi
echo ""

# --- CPU / Memory ---
echo "== CPU Usage =="
top -b -n1 | head -n 5
echo ""
echo "== Memory Usage =="
free -h
echo ""
echo "== Swap Usage =="
swapon --show || echo "No swap configured"
echo ""

# --- Disk usage ---
echo "== Disk Usage =="
df -hT
echo ""
echo "== Inodes Usage =="
df -i
echo ""

# --- Top processes ---
echo "== Top Processes by CPU =="
ps aux --sort=-%cpu | head -n 10
echo ""
echo "== Top Processes by Memory =="
ps aux --sort=-%mem | head -n 10
echo ""

# --- Network ---
echo "== Network Interfaces =="
ip -br addr
echo ""
echo "== Listening Ports =="
ss -tulnp
echo ""
echo "== Routing Table =="
ip route
echo ""
echo "== Last Connections =="
last -n 5
echo ""

# --- System logs (last 50 lines) ---
echo "== Syslog / Messages (last 50 lines) =="
if [[ -f /var/log/syslog ]]; then
  tail -n 50 /var/log/syslog
elif [[ -f /var/log/messages ]]; then
  tail -n 50 /var/log/messages
else
  echo "No syslog/messages found"
fi
echo ""

# --- Services status ---
echo "== Critical Services Status =="
SERVICES=("ssh" "nginx" "mysql")
for svc in "${SERVICES[@]}"; do
  if systemctl list-unit-files | grep -q "$svc"; then
    systemctl status "$svc" --no-pager | head -n 10
  else
    echo "Service $svc not installed"
  fi
  echo ""
done

echo "=============================="
echo "Troubleshooting report complete."
