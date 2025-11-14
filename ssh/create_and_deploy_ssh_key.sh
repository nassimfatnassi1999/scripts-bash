#!/bin/bash
# ==========================================================
# Script Name : create_and_deploy_ssh_key.sh
# Author      : Nassim Fatnassi (adapted)
# Description :
#   - Crée une paire de clés SSH (id_rsa / ed25519 / ecdsa)
#   - Sauvegarde la clé à l'emplacement spécifié
#   - Copie la clé publique sur une machine distante (ssh-copy-id ou fallback)
#   - Interactif : demande user@host, port, passphrase, etc.
# Compatible : Ubuntu / Pop!_OS / Debian
# ==========================================================

GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
CYAN="\e[36m"
NC="\e[0m"

print_header() {
    clear
    echo -e "${GREEN}=============================================="
    echo -e "     🔑 SSH Key Generator & Deployer"
    echo -e "==============================================${NC}"
}

ask_nonempty() {
    local prompt="$1"
    local __resultvar="$2"
    local val=""
    while true; do
        read -rp "$prompt" val
        if [[ -n "$val" ]]; then
            eval "$__resultvar='$val'"
            break
        else
            echo -e "${RED}⚠️  Ce champ ne peut pas être vide.${NC}"
        fi
    done
}

ask_yesno() {
    local prompt="$1"
    local __resultvar="$2"
    local val
    while true; do
        read -rp "$prompt (y/n): " val
        case "$val" in
            [Yy]*) eval "$__resultvar='y'"; break ;;
            [Nn]*) eval "$__resultvar='n'"; break ;;
            *) echo "Please answer y or n." ;;
        esac
    done
}

generate_key() {
    local key_type="$1"
    local key_bits="$2"
    local key_path="$3"
    local passphrase="$4"

    # Ensure directory exists
    mkdir -p "$(dirname "$key_path")"
    # If file exists, ask to overwrite
    if [[ -f "$key_path" ]]; then
        ask_yesno "Le fichier ${key_path} existe déjà. Voulez-vous l'écraser ?" overwrite
        if [[ "$overwrite" == "y" ]]; then
            rm -f "${key_path}" "${key_path}.pub"
        else
            echo -e "${YELLOW}Utilisez un autre nom ou chemin. Fin.${NC}"
            exit 1
        fi
    fi

    echo -e "${CYAN}→ Génération de la clé SSH (${key_type} ${key_bits}) dans : ${key_path}${NC}"

    if [[ -n "$passphrase" ]]; then
        ssh-keygen -t "$key_type" -b "$key_bits" -f "$key_path" -N "$passphrase" -q
    else
        ssh-keygen -t "$key_type" -b "$key_bits" -f "$key_path" -N "" -q
    fi

    if [[ $? -ne 0 ]]; then
        echo -e "${RED}❌ Échec de la génération de la clé.${NC}"
        exit 1
    fi

    echo -e "${GREEN}✅ Clé générée : ${key_path} et ${key_path}.pub${NC}"
}

copy_key_with_ssh_copy_id() {
    local pubfile="$1"
    local user="$2"
    local host="$3"
    local port="$4"

    if [[ -n "$port" ]]; then
        ssh-copy-id -i "$pubfile" -p "$port" "${user}@${host}"
    else
        ssh-copy-id -i "$pubfile" "${user}@${host}"
    fi
    return $?
}

copy_key_fallback() {
    # fallback: create ~/.ssh on remote and append the pubkey via ssh
    local pubfile="$1"
    local user="$2"
    local host="$3"
    local port="$4"

    PUB_CONTENT=$(cat "$pubfile")
    if [[ -n "$port" ]]; then
        ssh -p "$port" "${user}@${host}" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$PUB_CONTENT' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    else
        ssh "${user}@${host}" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$PUB_CONTENT' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    fi
    return $?
}

main() {
    print_header

    echo -e "${YELLOW}Étape 1 — Configuration de la clé locale${NC}"
    echo "Choix du type de clé :"
    echo "  1) ed25519 (recommandé)"
    echo "  2) rsa (compatibilité, configurable bits)"
    echo "  3) ecdsa"
    read -rp "Sélectionnez (1-3) [1]: " type_choice
    type_choice=${type_choice:-1}

    case "$type_choice" in
        1) KEY_TYPE="ed25519"; KEY_BITS="";;
        2) KEY_TYPE="rsa"; read -rp "Taille (bits) [4096]: " kb; KEY_BITS=${kb:-4096};;
        3) KEY_TYPE="ecdsa"; read -rp "Taille (bits) [521]: " kb; KEY_BITS=${kb:-521};;
        *) KEY_TYPE="ed25519"; KEY_BITS="";;
    esac

    ask_nonempty "Entrez le chemin complet pour la clé privée (ex: ~/.ssh/id_mykey): " KEY_PATH
    # expand ~
    KEY_PATH="${KEY_PATH/#\~/$HOME}"

    read -rp "Souhaitez-vous protéger la clé par une passphrase ? (laisser vide = pas de passphrase) : " PASSPHRASE
    # if user enters nothing, PASSPHRASE remains empty -> no passphrase

    echo -e "\n${YELLOW}Étape 2 — Destination distante${NC}"
    ask_nonempty "Entrez l'utilisateur distant (ex: ubuntu): " REMOTE_USER
    ask_nonempty "Entrez l'adresse distante (IP ou hostname) : " REMOTE_HOST
    read -rp "Entrez le port SSH distant (laisser vide pour 22) : " REMOTE_PORT

    echo -e "\n${YELLOW}Confirmation:${NC}"
    echo -e "  Clé : ${KEY_TYPE} ${KEY_BITS} -> ${KEY_PATH}"
    echo -e "  Remote : ${REMOTE_USER}@${REMOTE_HOST} ${REMOTE_PORT:+port $REMOTE_PORT}"
    ask_yesno "Confirmer et générer + copier la clé ?" proceed
    if [[ "$proceed" != "y" ]]; then
        echo -e "${YELLOW}Abandon.${NC}"
        exit 0
    fi

    # Generate key
    generate_key "$KEY_TYPE" "$KEY_BITS" "$KEY_PATH" "$PASSPHRASE"

    echo -e "\n${YELLOW}Étape 3 — Copie de la clé publique sur la machine distante${NC}"
    PUBFILE="${KEY_PATH}.pub"
    if [[ ! -f "$PUBFILE" ]]; then
        echo -e "${RED}❌ Fichier ${PUBFILE} introuvable.${NC}"
        exit 1
    fi

    # Try ssh-copy-id first
    if command -v ssh-copy-id &>/dev/null; then
        echo -e "${CYAN}→ Utilisation de ssh-copy-id (si la machine distante demande mot de passe, entrez-le)${NC}"
        copy_key_with_ssh_copy_id "$PUBFILE" "$REMOTE_USER" "$REMOTE_HOST" "$REMOTE_PORT"
        rc=$?
        if [[ $rc -ne 0 ]]; then
            echo -e "${YELLOW}⚠️  ssh-copy-id a échoué (code $rc). Tentative de fallback...${NC}"
            copy_key_fallback "$PUBFILE" "$REMOTE_USER" "$REMOTE_HOST" "$REMOTE_PORT"
            rc=$?
            if [[ $rc -ne 0 ]]; then
                echo -e "${RED}❌ Échec de la copie de la clé publique (fallback). Vérifiez la connectivité et que SSH est accessible.${NC}"
                exit 1
            fi
        fi
    else
        echo -e "${YELLOW}ℹ️  ssh-copy-id non trouvé. Utilisation du fallback (ssh + append).${NC}"
        copy_key_fallback "$PUBFILE" "$REMOTE_USER" "$REMOTE_HOST" "$REMOTE_PORT"
        rc=$?
        if [[ $rc -ne 0 ]]; then
            echo -e "${RED}❌ Échec de la copie de la clé publique (fallback).${NC}"
            exit 1
        fi
    fi

    echo -e "${GREEN}✅ Clé publique copiée sur ${REMOTE_USER}@${REMOTE_HOST}${NC}"

    echo -e "\n${CYAN}Résumé:${NC}"
    echo -e "  Clé privée locale : ${KEY_PATH}"
    echo -e "  Clé publique locale: ${PUBFILE}"
    echo -e "  Déployée sur     : ${REMOTE_USER}@${REMOTE_HOST} ${REMOTE_PORT:+port $REMOTE_PORT}"
    echo -e "\nTest rapide :"
    if [[ -n "$REMOTE_PORT" ]]; then
        echo -e "  ssh -i ${KEY_PATH} -p ${REMOTE_PORT} ${REMOTE_USER}@${REMOTE_HOST}"
    else
        echo -e "  ssh -i ${KEY_PATH} ${REMOTE_USER}@${REMOTE_HOST}"
    fi

    echo -e "\n${GREEN}Terminé.${NC}"
}

main "$@"
