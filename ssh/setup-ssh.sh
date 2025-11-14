#!/bin/bash
# ==========================================================
# Script Name : setup-ssh.sh
# Author      : Nassim Fatnassi
# Description :
#   - Vérifie, installe et configure le service SSH
#   - Active l’accès root / utilisateur selon choix
#   - Ouvre le port 22 via UFW avec options de sécurité
#   - Compatible : Ubuntu / Pop!_OS
# ==========================================================

# ---------- COLORS ---------- #
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
CYAN="\e[36m"
NC="\e[0m"

# ---------- FUNCTIONS ---------- #

print_header() {
    clear
    echo -e "${GREEN}=============================================="
    echo -e "     🔐 SSH Server Automated Setup Utility"
    echo -e "==============================================${NC}"
}

pause() {
    read -rp "Appuyez sur Entrée pour continuer..." _
}

check_ssh_installed() {
    echo -e "${CYAN}🔎 Vérification du service SSH...${NC}"
    if dpkg -s openssh-server &> /dev/null; then
        echo -e "${GREEN}✅ SSH est déjà installé.${NC}"
    else
        echo -e "${RED}❌ SSH n’est pas installé.${NC}"
        read -p "Souhaitez-vous installer le service SSH ? (y/n): " install_choice
        if [[ "$install_choice" == "y" ]]; then
            sudo apt update && sudo apt install -y openssh-server
            echo -e "${GREEN}✅ SSH installé avec succès.${NC}"
        else
            echo -e "${YELLOW}🚫 Installation annulée. Fin du script.${NC}"
            exit 0
        fi
    fi
}

enable_ssh_service() {
    echo -e "${CYAN}⚙️  Activation du service SSH...${NC}"
    sudo systemctl enable ssh
    sudo systemctl start ssh

    if systemctl is-active --quiet ssh; then
        echo -e "${GREEN}✅ Le service SSH est actif.${NC}"
    else
        echo -e "${RED}❌ Erreur : SSH n’a pas pu démarrer.${NC}"
        exit 1
    fi
}

configure_firewall() {
    echo -e "${CYAN}🧱 Configuration du pare-feu (UFW)...${NC}"
    if ! command -v ufw &>/dev/null; then
        echo -e "${YELLOW}→ UFW non installé, installation en cours...${NC}"
        sudo apt install -y ufw
    fi

    read -p "Souhaitez-vous ouvrir le port SSH (22) dans le pare-feu ? (y/n): " ufw_choice
    if [[ "$ufw_choice" == "y" ]]; then
        sudo ufw allow ssh
        sudo ufw reload
        echo -e "${GREEN}✅ Port SSH (22) autorisé via UFW.${NC}"
    else
        echo -e "${YELLOW}⚠️  Port SSH non ouvert (vous devrez le faire manuellement si nécessaire).${NC}"
    fi
}

configure_ssh_permissions() {
    SSH_CONFIG="/etc/ssh/sshd_config"

    echo -e "${CYAN}🔧 Configuration des permissions SSH...${NC}"

    # --- Root Login ---
    read -p "Souhaitez-vous autoriser la connexion SSH du compte root ? (y/n): " root_choice
    if [[ "$root_choice" == "y" ]]; then
        sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' "$SSH_CONFIG"
        echo -e "${GREEN}✅ Connexion SSH root autorisée.${NC}"
    else
        sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' "$SSH_CONFIG"
        echo -e "${YELLOW}🚫 Connexion root désactivée.${NC}"
    fi

    # --- Password Authentication ---
    read -p "Souhaitez-vous activer l’authentification par mot de passe ? (y/n): " pass_choice
    if [[ "$pass_choice" == "y" ]]; then
        sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' "$SSH_CONFIG"
        echo -e "${GREEN}✅ Authentification par mot de passe activée.${NC}"
    else
        sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' "$SSH_CONFIG"
        echo -e "${YELLOW}🔒 Authentification par mot de passe désactivée (clé SSH uniquement).${NC}"
    fi
}

configure_access_scope() {
    echo -e "${CYAN}🌍 Configuration de la portée d’accès SSH...${NC}"
    read -p "Voulez-vous autoriser TOUTES les adresses IP à accéder en SSH ? (y/n): " open_choice

    if [[ "$open_choice" == "y" ]]; then
        sudo ufw allow from any to any port 22 proto tcp
        echo -e "${YELLOW}⚠️  SSH ouvert à tout le monde (non recommandé pour la production).${NC}"
    else
        read -p "Entrez le réseau autorisé (ex: 192.168.1.0/24) : " subnet
        if [[ -n "$subnet" ]]; then
            sudo ufw allow from "$subnet" to any port 22 proto tcp
            echo -e "${GREEN}✅ Accès SSH autorisé uniquement pour ${subnet}.${NC}"
        else
            echo -e "${YELLOW}⚠️  Aucun réseau ajouté, règles UFW inchangées.${NC}"
        fi
    fi
}

restart_ssh() {
    echo -e "${CYAN}♻️  Redémarrage du service SSH...${NC}"
    sudo systemctl restart ssh
    sleep 1
    if systemctl is-active --quiet ssh; then
        echo -e "${GREEN}✅ SSH redémarré avec succès.${NC}"
    else
        echo -e "${RED}❌ Erreur : SSH ne s’est pas relancé correctement.${NC}"
        exit 1
    fi
}

display_summary() {
    echo -e "\n${GREEN}🎉 Configuration SSH terminée avec succès !${NC}"
    echo -e "${CYAN}--------------------------------------------${NC}"

    # 🧠 Récupérer toutes les IP locales sauf 127.0.0.1
    IP_LIST=$(hostname -I | tr ' ' '\n' | grep -v '^127\.' | sort -u)

    echo -e "${YELLOW}📡 Adresses IP locales détectées :${NC}"
    echo -e "${CYAN}--------------------------------------------${NC}"
    i=1
    for ip in $IP_LIST; do
        echo -e "  ${GREEN}#${i}${NC}  🌐 ${ip}"
        ((i++))
    done
    echo -e "${CYAN}--------------------------------------------${NC}"

    echo -e "${YELLOW}🔌 Port SSH :${NC} 22"
    echo -e "${YELLOW}📁 Fichier config :${NC} /etc/ssh/sshd_config"
    echo -e "${YELLOW}🚀 Tester depuis un autre appareil :${NC}"

    for ip in $IP_LIST; do
        echo -e "    ssh <utilisateur>@${ip}"
    done

    echo -e "${CYAN}--------------------------------------------${NC}"
    echo -e "${GREEN}✅ Votre serveur SSH est prêt à accepter les connexions.${NC}"
}


# ---------- MAIN SCRIPT ---------- #
print_header
check_ssh_installed
enable_ssh_service
configure_firewall
configure_ssh_permissions
configure_access_scope
restart_ssh
display_summary
