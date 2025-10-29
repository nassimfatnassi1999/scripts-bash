#!/bin/bash
# ==========================================================
# Script Name : rsync-backup.sh
# Author      : Nassim Fatnassi
# Description :
#   - Installs Rsync if not already installed
#   - Checks or creates SSH key pair
#   - Copies SSH public key to remote VM (if needed)
#   - Validates user input (no empty answers)
#   - Performs Rsync backup and optional scheduling
# ==========================================================

# ---------- COLORS ---------- #
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
NC="\e[0m"

# ---------- FUNCTIONS ---------- #

# ✅ Check if Rsync is installed
check_rsync() {
    echo -e "${GREEN}=== Checking Rsync installation ===${NC}"
    if ! command -v rsync &> /dev/null; then
        echo -e "${YELLOW}Installing Rsync...${NC}"
        sudo apt update -y && sudo apt install -y rsync
    else
        echo -e "${GREEN}Rsync is already installed.${NC}"
    fi
}

# ✅ Ensure SSH key exists (or create one)
check_ssh_key() {
    echo -e "${GREEN}=== Checking SSH key ===${NC}"
    SSH_KEY="$HOME/.ssh/id_rsa.pub"
    if [ ! -f "$SSH_KEY" ]; then
        echo -e "${YELLOW}No SSH public key found.${NC}"
        read -p "Would you like to generate one now? (Y/N): " GENKEY
        if [[ "$GENKEY" =~ ^[Yy]$ ]]; then
            mkdir -p "$HOME/.ssh"
            ssh-keygen -t rsa -b 4096 -C "$USER@$(hostname)" -N "" -f "$HOME/.ssh/id_rsa"
            echo -e "${GREEN}SSH key generated successfully.${NC}"
        else
            echo -e "${RED}Cannot continue without SSH key.${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}SSH key already exists.${NC}"
    fi
}

# ✅ Fix permissions remotely (for Azure, Ubuntu, etc.)
fix_remote_ssh_permissions() {
    echo -e "${GREEN}=== Fixing SSH permissions on remote VM ===${NC}"
    ssh "$REMOTE_USER@$REMOTE_IP" << EOF
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
        touch ~/.ssh/authorized_keys
        chmod 600 ~/.ssh/authorized_keys
        chown -R \$USER:\$USER ~/.ssh
EOF
    echo -e "${GREEN}SSH permissions fixed successfully on remote VM.${NC}"
}

# ✅ Copy SSH key if needed (and repair permissions)
copy_ssh_key() {
    echo -e "${GREEN}=== Checking SSH connection ===${NC}"
    ssh -q -o BatchMode=yes -o ConnectTimeout=5 "$REMOTE_USER@$REMOTE_IP" exit
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}SSH connection failed. Possibly missing SSH key authentication.${NC}"
        read -p "Would you like to copy your SSH public key to the remote VM? (Y/N): " COPYKEY
        if [[ "$COPYKEY" =~ ^[Yy]$ ]]; then
            fix_remote_ssh_permissions
            echo -e "${YELLOW}Copying your public key to $REMOTE_USER@$REMOTE_IP...${NC}"
            ssh-copy-id -i "$HOME/.ssh/id_rsa.pub" "$REMOTE_USER@$REMOTE_IP"
            fix_remote_ssh_permissions
            echo -e "${GREEN}Public key copied successfully and permissions fixed.${NC}"
        else
            echo -e "${RED}SSH authentication will not work without the key.${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}SSH connection already works. Skipping key copy.${NC}"
    fi
}

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

# ✅ Perform Rsync backup
run_rsync_backup() {
    echo -e "${GREEN}=== Starting Rsync Backup ===${NC}"
    ssh "$REMOTE_USER@$REMOTE_IP" "mkdir -p $REMOTE_DIR"
    rsync -avz -e ssh "$LOCAL_DIR/" "$REMOTE_USER@$REMOTE_IP:$REMOTE_DIR/"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Backup completed successfully to $REMOTE_IP:$REMOTE_DIR${NC}"
    else
        echo -e "${RED}❌ Backup failed.${NC}"
    fi
}

# ✅ Optional scheduling (cron)
schedule_backup() {
    echo
    read -p "⏰ Would you like to schedule this backup daily? (Y/N): " REP
    if [[ "$REP" =~ ^[Yy]$ ]]; then
        CRON_CMD="rsync -avz -e ssh $LOCAL_DIR/ $REMOTE_USER@$REMOTE_IP:$REMOTE_DIR/"
        (crontab -l 2>/dev/null; echo "0 2 * * * $CRON_CMD") | crontab -
        echo -e "${GREEN}Backup scheduled daily at 02:00 AM.${NC}"
    fi
}

# ---------- MAIN SCRIPT ---------- #

echo -e "${GREEN}=== Rsync Secure Backup Setup ===${NC}"
check_rsync
check_ssh_key

# User input (non-empty)
ask_input "🧑 Enter the remote VM username: " REMOTE_USER
ask_input "🌐 Enter the remote VM IP address: " REMOTE_IP
ask_input "📁 Enter the local folder to back up (e.g. /home/nassim/Documents): " LOCAL_DIR
ask_input "📁 Enter the destination folder on the remote VM (e.g. /home/$REMOTE_USER/backup): " REMOTE_DIR

# Verify local folder
if [ ! -d "$LOCAL_DIR" ]; then
    echo -e "${RED}Error: local directory $LOCAL_DIR does not exist.${NC}"
    exit 1
fi

copy_ssh_key
run_rsync_backup
schedule_backup

