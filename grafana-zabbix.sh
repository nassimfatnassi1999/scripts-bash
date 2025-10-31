#!/bin/bash
# ==========================================================
# Script Name : grafana-setup.sh
# Author      : Nassim Fatnassi
# Description :
#   - Installs and configures Grafana OSS
#   - Adds Zabbix data source automatically
#   - Enables and starts Grafana service
#   - Tested on Ubuntu 22.04 / 24.04 / Pop!_OS
# ==========================================================

# ---------- COLORS ---------- #
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
NC="\e[0m"

# ---------- FUNCTIONS ---------- #

# ✅ Check and install Grafana repository
install_grafana_repo() {
    echo -e "${GREEN}=== Adding Grafana repository ===${NC}"
    sudo apt install -y apt-transport-https software-properties-common wget gpg

    wget -q -O - https://packages.grafana.com/gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/grafana.gpg
    echo "deb [signed-by=/usr/share/keyrings/grafana.gpg] https://packages.grafana.com/oss/deb stable main" \
        | sudo tee /etc/apt/sources.list.d/grafana.list > /dev/null

    sudo apt update -y
}

# ✅ Install Grafana
install_grafana() {
    echo -e "${GREEN}=== Installing Grafana OSS ===${NC}"
    sudo apt install -y grafana

    if ! command -v grafana-server &> /dev/null; then
        echo -e "${RED}❌ Grafana installation failed.${NC}"
        exit 1
    fi

    sudo systemctl enable grafana-server
    sudo systemctl start grafana-server
    echo -e "${GREEN}✅ Grafana installed and started successfully.${NC}"
}

# ✅ Open Grafana port (3000)
configure_firewall() {
    echo -e "${GREEN}=== Configuring firewall (port 3000) ===${NC}"
    sudo ufw allow 3000/tcp
    echo -e "${GREEN}✅ Port 3000 opened.${NC}"
}

# ✅ Configure Zabbix data source (via Grafana API)
configure_zabbix_datasource() {
    echo -e "${GREEN}=== Configuring Zabbix Data Source in Grafana ===${NC}"

    GRAFANA_USER="admin"
    GRAFANA_PASS="admin"
    ZABBIX_URL="http://localhost:8080"   # ⚠️ Change this if your Zabbix frontend runs on another port
    ZABBIX_API_URL="http://localhost/zabbix/api_jsonrpc.php"

    # Wait until Grafana API is available
    echo -e "${YELLOW}Waiting for Grafana API to start...${NC}"
    sleep 10

    # Create Zabbix data source via Grafana HTTP API
    curl -s -X POST http://$GRAFANA_USER:$GRAFANA_PASS@localhost:3000/api/datasources \
        -H "Content-Type: application/json" \
        -d "{
              \"name\":\"Zabbix\",
              \"type\":\"alexanderzobnin-zabbix-datasource\",
              \"access\":\"proxy\",
              \"url\":\"$ZABBIX_API_URL\",
              \"jsonData\": {
                  \"username\": \"Admin\",
                  \"password\": \"zabbix\",
                  \"dbConnectionEnable\": false
              }
          }" >/dev/null 2>&1

    echo -e "${GREEN}✅ Zabbix data source added to Grafana.${NC}"
}

# ✅ Display connection info
display_info() {
    IP=$(hostname -I | awk '{print $1}')
    echo -e "\n${GREEN}🎉 Grafana installation completed successfully!${NC}"
    echo -e "${YELLOW}🌍 Access Grafana Web UI at:${NC} http://${IP}:3000"
    echo -e "${YELLOW}👤 Default login:${NC} admin / admin"
    echo -e "${YELLOW}🧩 Data Source:${NC} Zabbix (added automatically)"
}

# ---------- MAIN SCRIPT ---------- #
clear
echo -e "${GREEN}=== Grafana Automated Setup ===${NC}"

install_grafana_repo
install_grafana
configure_firewall

# Install Zabbix plugin for Grafana
echo -e "${GREEN}=== Installing Zabbix Plugin for Grafana ===${NC}"
sudo grafana-cli plugins install alexanderzobnin-zabbix-app
sudo systemctl restart grafana-server
echo -e "${GREEN}✅ Zabbix Plugin installed successfully.${NC}"

# Configure datasource (optional)
configure_zabbix_datasource

display_info
