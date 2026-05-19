#!/bin/bash
# ==========================================================
# Script Name : zabbix-agent-setup.sh
# Author      : Nassim Fatnassi
# Description :
#   - Installs and configures Zabbix Agent (Linux)
#   - Supports Ubuntu/Debian systems
#   - Validates user input (no empty answers)
#   - Configures server IP and hostname
#   - Starts and enables Zabbix Agent service
# ==========================================================

# ---------- COLORS ---------- #
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
NC="\e[0m"

if ! command -v apt >/dev/null 2>&1; then
    echo -e "${RED}This script supports only apt-based systems (Ubuntu/Debian/Pop!_OS).${NC}"
    exit 1
fi

# ---------- FUNCTIONS ---------- #

# ✅ Validate user input (prevent empty entries)
ask_input() {
    local prompt="$1"
    local var_name="$2"
    local value=""
    while true; do
        read -p "$prompt" value
        if [ -n "$value" ]; then
            eval "$var_name='$value'"
            break
        else
            echo -e "${RED}⚠️  This field cannot be empty. Please enter a value.${NC}"
        fi
    done
}

# ✅ Install Zabbix Agent (robust version)
check_zabbix_agent() {
    echo -e "${GREEN}=== Checking Zabbix Agent installation ===${NC}"
    if ! command -v zabbix_agentd &> /dev/null; then
        echo -e "${YELLOW}Installing Zabbix Agent 6.4...${NC}"
        
        # Detect Ubuntu version dynamically
        UBUNTU_VER="$(lsb_release -rs)"
        ZBX_VER="6.4"
        PKG_FILE="/tmp/zabbix-release_${ZBX_VER}-1+ubuntu${UBUNTU_VER}_all.deb"

        # Download and install repository
        wget -q "https://repo.zabbix.com/zabbix/${ZBX_VER}/ubuntu/pool/main/z/zabbix-release_${ZBX_VER}-1+ubuntu${UBUNTU_VER}_all.deb" -O "$PKG_FILE"
        if [ -f "$PKG_FILE" ]; then
            sudo dpkg -i "$PKG_FILE"
        else
            echo -e "${YELLOW}⚠️ Repository package not found for your version. Using default Ubuntu repo.${NC}"
        fi

        sudo apt update -y
        sudo apt install -y zabbix-agent

        if ! command -v zabbix_agentd &> /dev/null; then
            echo -e "${RED}❌ Failed to install Zabbix Agent.${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}Zabbix Agent is already installed.${NC}"
    fi
}

# ✅ Configure Zabbix Agent
configure_agent() {
    echo -e "${GREEN}=== Configuring Zabbix Agent ===${NC}"

    CONFIG_FILE="/etc/zabbix/zabbix_agentd.conf"

    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}❌ Configuration file not found: $CONFIG_FILE${NC}"
        exit 1
    fi

    sudo sed -i "s/^Server=.*/Server=$ZABBIX_SERVER_IP/" "$CONFIG_FILE"
    sudo sed -i "s/^ServerActive=.*/ServerActive=$ZABBIX_SERVER_IP/" "$CONFIG_FILE"
    sudo sed -i "s/^Hostname=.*/Hostname=$HOSTNAME_CUSTOM/" "$CONFIG_FILE"

    echo -e "${YELLOW}Configuration updated:${NC}"
    grep -E 'Server|ServerActive|Hostname' "$CONFIG_FILE" | grep -v '^#'
}

# ✅ Start and enable Zabbix Agent service
start_service() {
    echo -e "${GREEN}=== Starting Zabbix Agent service ===${NC}"
    sudo systemctl enable zabbix-agent
    sudo systemctl restart zabbix-agent

    if systemctl is-active --quiet zabbix-agent; then
        echo -e "${GREEN}✅ Zabbix Agent is running.${NC}"
    else
        echo -e "${RED}❌ Failed to start Zabbix Agent.${NC}"
        sudo journalctl -u zabbix-agent --no-pager | tail -n 10
        exit 1
    fi
}

# ✅ Show agent status and version
show_status() {
    echo -e "${GREEN}=== Zabbix Agent Status ===${NC}"
    systemctl status zabbix-agent --no-pager | grep -E 'Active|Loaded'
    echo -e "${GREEN}\nAgent Version:${NC} $(zabbix_agentd -V | head -n1)"
}

# ---------- MAIN SCRIPT ---------- #
clear
echo -e "${GREEN}=== Zabbix Agent Installation & Configuration ===${NC}"

ask_input "🌐 Enter Zabbix Server IP Address: " ZABBIX_SERVER_IP
ask_input "💻 Enter this machine's hostname (for Zabbix UI): " HOSTNAME_CUSTOM

check_zabbix_agent
configure_agent
start_service
show_status

echo -e "\n${GREEN}🎉 Zabbix Agent successfully installed and configured!${NC}"
echo -e "${YELLOW}➡️  Add this host in your Zabbix Server UI using hostname: ${HOSTNAME_CUSTOM}${NC}"
echo -e "${YELLOW}➡️  Server IP configured: ${ZABBIX_SERVER_IP}${NC}"
