#!/bin/bash
# ==========================================================
# Script Name : zabbix-server-remove.sh
# Author      : Nassim Fatnassi
# Description :
#   - Uninstalls and cleans all Zabbix Server components
#   - Removes: Zabbix Server + MariaDB + Apache + config + repo
#   - Tested on Ubuntu 22.04 / 24.04 / Pop!_OS
# ==========================================================

# ---------- COLORS ---------- #
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
NC="\e[0m"

# ---------- CONFIRMATION ---------- #
echo -e "${RED}⚠️  WARNING: This will completely remove Zabbix Server, database, and configuration files.${NC}"
read -p "Are you sure you want to continue? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Operation cancelled.${NC}"
    exit 0
fi

# ---------- FUNCTIONS ---------- #

stop_services() {
    echo -e "${GREEN}=== Stopping Zabbix, Apache, and MariaDB services ===${NC}"
    sudo systemctl stop zabbix-server zabbix-agent apache2 mariadb 2>/dev/null || true
}

remove_packages() {
    echo -e "${GREEN}=== Removing Zabbix and related packages ===${NC}"
    sudo apt purge -y zabbix-server-mysql zabbix-agent zabbix-frontend-php \
        zabbix-apache-conf zabbix-sql-scripts mariadb-server mariadb-client apache2
    sudo apt autoremove -y
}

remove_database() {
    echo -e "${GREEN}=== Removing Zabbix Database and User (MariaDB) ===${NC}"
    sudo mysql -e "DROP DATABASE IF EXISTS zabbix;"
    sudo mysql -e "DROP USER IF EXISTS 'zabbix'@'localhost';"
    sudo mysql -e "FLUSH PRIVILEGES;"
}

clean_files() {
    echo -e "${GREEN}=== Cleaning residual configuration and logs ===${NC}"
    sudo rm -rf /etc/zabbix /var/log/zabbix /var/lib/mysql /etc/mysql
    sudo rm -f /etc/apt/sources.list.d/zabbix.list
    sudo rm -f /usr/share/keyrings/zabbix.gpg
    sudo rm -rf /var/www/html/zabbix
}

reload_system() {
    echo -e "${GREEN}=== Reloading system and cleaning cache ===${NC}"
    sudo systemctl daemon-reload
    sudo apt update -y
    sudo apt clean
}

final_message() {
    echo -e "\n${YELLOW}✅ Zabbix Server and all components have been completely removed.${NC}"
    echo -e "${YELLOW}You can reinstall it anytime using: ${GREEN}./zabbix-server-setup.sh${NC}"
}

# ---------- MAIN SCRIPT ---------- #
stop_services
remove_packages
remove_database
clean_files
reload_system
final_message
