#!/bin/bash
# ==========================================================
# Script Name : grafana-remove.sh
# Author      : Nassim Fatnassi
# Description :
#   - Uninstalls and cleans all Grafana components
#   - Removes Grafana service, plugins, configs, repo, logs
#   - Tested on Ubuntu 22.04 / 24.04 / Pop!_OS
# ==========================================================

# ---------- COLORS ---------- #
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
NC="\e[0m"

# ---------- CONFIRMATION ---------- #
echo -e "${RED}⚠️  WARNING: This will completely remove Grafana, its configuration, and all dashboards.${NC}"
read -p "Are you sure you want to continue? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Operation cancelled.${NC}"
    exit 0
fi

# ---------- FUNCTIONS ---------- #

stop_services() {
    echo -e "${GREEN}=== Stopping Grafana service ===${NC}"
    sudo systemctl stop grafana-server 2>/dev/null || true
    sudo systemctl disable grafana-server 2>/dev/null || true
}

remove_packages() {
    echo -e "${GREEN}=== Removing Grafana packages ===${NC}"
    sudo apt purge -y grafana
    sudo apt autoremove -y
    sudo apt clean
}

remove_files() {
    echo -e "${GREEN}=== Removing Grafana configuration, logs and plugins ===${NC}"
    sudo rm -rf /etc/grafana
    sudo rm -rf /var/lib/grafana
    sudo rm -rf /var/log/grafana
    sudo rm -f /etc/apt/sources.list.d/grafana.list
    sudo rm -f /usr/share/keyrings/grafana.gpg
}

firewall_cleanup() {
    echo -e "${GREEN}=== Removing Grafana firewall rule (port 3000) ===${NC}"
    sudo ufw delete allow 3000/tcp 2>/dev/null || true
}

reload_system() {
    echo -e "${GREEN}=== Reloading system configuration ===${NC}"
    sudo systemctl daemon-reload
    sudo apt update -y
}

final_message() {
    echo -e "\n${YELLOW}✅ Grafana has been completely removed from this system.${NC}"
    echo -e "${YELLOW}You can reinstall it anytime using:${NC} ${GREEN}./grafana-setup.sh${NC}"
}

# ---------- MAIN SCRIPT ---------- #
stop_services
remove_packages
remove_files
firewall_cleanup
reload_system
final_message
