#!/usr/bin/env bash

# ==========================================================
# Script Name : ansible.sh
# Author      : Nassim Fatnassi
# Description :
#   - Mise à jour des paquets
#   - Installation des dépendances nécessaires
#   - Ajout du dépôt officiel Ansible
#   - Installation d'Ansible
# ==========================================================


# Arrêt en cas d'erreur
set -e

echo "🚀 Installation de Ansible sur Pop!_OS..."

# Vérification des privilèges
if [[ $EUID -ne 0 ]]; then
  echo "❌ Ce script doit être exécuté avec les privilèges administrateur (sudo)."
  echo "👉 Essayez : sudo $0"
  exit 1
fi

# Mise à jour des paquets
echo "🔄 Mise à jour du système..."
apt update -y && apt upgrade -y

# Installation des dépendances nécessaires
echo "📦 Installation des dépendances..."
apt install -y software-properties-common curl

# Ajout du dépôt officiel Ansible
echo "🗂️ Ajout du dépôt officiel Ansible..."
add-apt-repository --yes --update ppa:ansible/ansible

# Installation d'Ansible
echo "⬇️ Installation d'Ansible..."
apt install -y ansible

# Vérification de l'installation
echo "✅ Vérification..."
ansible --version

echo "🎉 Ansible a été installé avec succès sur Pop!_OS."
