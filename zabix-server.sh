#!/bin/bash
# ==========================================================
# Script Name : zabbix-server-setup.sh
# Author      : Nassim Fatnassi
# Description :
#   - Installs and configures a full Zabbix Server (v6.4)
#   - Components: Zabbix Server + MariaDB + Apache + PHP + Agent
#   - Tested on Ubuntu 22.04 / 24.04 / Pop!_OS
# ==========================================================

# ---------- COLORS ---------- #
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
NC="\e[0m"

# ---------- FUNCTIONS ---------- #

ask_input() {
    local prompt="$1"
    local var_name="$2"
    local value=""
    while true; do
        read -rp "$prompt" value
        if [ -n "$value" ]; then
            eval "$var_name='$value'"
            break
        else
            echo -e "${RED}⚠️  This field cannot be empty.${NC}"
        fi
    done
}

install_zabbix_server() {
    echo -e "${GREEN}=== Installing Zabbix Server and dependencies ===${NC}"

    UBUNTU_CODENAME=$(lsb_release -cs)
    ZBX_VER="6.4"

    echo -e "${YELLOW}→ Adding official Zabbix repository for Ubuntu ${UBUNTU_CODENAME}${NC}"

    # Import GPG key & add repo in a robust way
    wget -qO- https://repo.zabbix.com/zabbix-official-repo.key | sudo gpg --dearmor -o /usr/share/keyrings/zabbix.gpg
    echo "deb [signed-by=/usr/share/keyrings/zabbix.gpg] https://repo.zabbix.com/zabbix/${ZBX_VER}/ubuntu ${UBUNTU_CODENAME} main" | \
        sudo tee /etc/apt/sources.list.d/zabbix.list > /dev/null

    sudo apt update -y
    sudo apt install -y mariadb-server mariadb-client \
        zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf \
        zabbix-sql-scripts zabbix-agent || {
        echo -e "${RED}❌ Zabbix Server installation failed. Check your network or repo configuration.${NC}"
        exit 1
    }

    echo -e "${GREEN}✅ Zabbix packages installed successfully.${NC}"
}

configure_database() {
    echo -e "${GREEN}=== Configuring MariaDB for Zabbix ===${NC}"
    sudo systemctl enable mariadb
    sudo systemctl start mariadb

    sudo mysql -e "CREATE DATABASE zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;"
    sudo mysql -e "CREATE USER 'zabbix'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';"
    sudo mysql -e "GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';"
    sudo mysql -e "FLUSH PRIVILEGES;"

    echo -e "${YELLOW}✅ Database 'zabbix' and user created successfully.${NC}"
}

import_schema() {
    echo -e "${GREEN}=== Importing Zabbix SQL schema ===${NC}"
    if [ -f /usr/share/zabbix-sql-scripts/mysql/server.sql.gz ]; then
        zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | mysql -uzabbix -p"${DB_PASSWORD}" zabbix
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✅ Zabbix database schema imported successfully.${NC}"
        else
            echo -e "${RED}❌ Failed to import schema. Please check your DB password.${NC}"
            exit 1
        fi
    else
        echo -e "${RED}❌ Schema file not found!${NC}"
        exit 1
    fi
}

configure_server() {
    echo -e "${GREEN}=== Configuring Zabbix Server ===${NC}"
    CONFIG_FILE="/etc/zabbix/zabbix_server.conf"
    sudo sed -i "s/^# DBPassword=.*/DBPassword=${DB_PASSWORD}/" "$CONFIG_FILE"
    sudo sed -i "s/^# DBHost=.*/DBHost=localhost/" "$CONFIG_FILE"

    echo -e "${YELLOW}✅ Zabbix Server configuration updated.${NC}"
}

start_services() {
    echo -e "${GREEN}=== Starting Zabbix and Apache services ===${NC}"
    sudo systemctl restart zabbix-server zabbix-agent apache2
    sudo systemctl enable zabbix-server zabbix-agent apache2

    if systemctl is-active --quiet zabbix-server; then
        echo -e "${GREEN}✅ Zabbix Server is running.${NC}"
    else
        echo -e "${RED}❌ Zabbix Server failed to start.${NC}"
        sudo journalctl -u zabbix-server --no-pager | tail -n 10
        exit 1
    fi
}

display_info() {
    SERVER_IP=$(hostname -I | awk '{print $1}')
    echo -e "\n${GREEN}🎉 Zabbix Server installation completed successfully!${NC}"
    echo -e "${YELLOW}🌍 Access Zabbix Web Interface at:${NC} http://${SERVER_IP}/zabbix"
    echo -e "${YELLOW}👤 Default Login:${NC} Admin / zabbix"
    echo -e "${YELLOW}🗄️  Database User:${NC} zabbix"
    echo -e "${YELLOW}🔑 Database Password:${NC} ${DB_PASSWORD}"
}

# ---------- MAIN SCRIPT ---------- #
clear
echo -e "${GREEN}=== Zabbix Server Automated Setup ===${NC}"

ask_input "🔑 Enter a password for Zabbix database user: " DB_PASSWORD

install_zabbix_server
configure_database
import_schema
configure_server
start_services
display_info

