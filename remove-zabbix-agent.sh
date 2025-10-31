#!/bin/bash
# ==========================================================
# Script Name : zabbix-agent-remove.sh
# Author      : Nassim Fatnassi
# Description :
#   - Uninstalls and cleans Zabbix Agent from a Linux host
#   - Tested on Ubuntu / Debian systems
# ==========================================================

# ---------- COLORS ---------- #
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
NC="\e[0m"

# ---------- CONFIRMATION ---------- #
echo -e "${RED}⚠️  WARNING: This will completely remove Zabbix Agent and its configuration files.${NC}"
read -p "Are you sure you want to continue? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Operation cancelled.${NC}"
    exit 0
fi

# ---------- FUNCTIONS ---------- #

stop_service() {
    echo -e "${GREEN}=== Stopping Zabbix Agent service ===${NC}"
    sudo systemctl stop zabbix-agent 2>/dev/null || true
    sudo systemctl disable zabbix-agent 2>/dev/null || true
}

remove_package() {
    echo -e "${GREEN}=== Removing Zabbix Agent package ===${NC}"
    sudo apt purge -y zabbix-agent
    sudo apt autoremove -y
    sudo apt clean
}

remove_repo() {
    echo -e "${GREEN}=== Removing Zabbix repository and key ===${NC}"
    sudo rm -f /etc/apt/sources.list.d/zabbix.list
    sudo rm -f /usr/share/keyrings/zabbix.gpg
    sudo rm -f /tmp/zabbix-release*.deb
    sudo apt update -y
}

clean_files() {
    echo -e "${GREEN}=== Cleaning configuration and logs ===${NC}"
    sudo rm -rf /etc/zabbix
    sudo rm -rf /var/log/zabbix
    sudo rm -rf /var/lib/zabbix
}

reload_system() {
    echo -e "${GREEN}=== Reloading system configuration ===${NC}"
    sudo systemctl daemon-reload
}

final_message() {
    echo -e "\n${YELLOW}✅ Zabbix Agent has been completely removed from this system.${NC}"
    echo -e "${YELLOW}You can reinstall it anytime using:${NC} ${GREEN}./zabbix-agent-setup.sh${NC}"
}

# ---------- MAIN SCRIPT ---------- #
stop_service
remove_package
remove_repo
clean_files
reload_system
final_message
