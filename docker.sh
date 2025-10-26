#!/usr/bin/env bash

set -e

echo "🚀 Installation de Docker et Docker Compose sur Pop!_OS"

# Vérification des privilèges
if [[ $EUID -ne 0 ]]; then
  echo "❌ Ce script doit être exécuté avec sudo."
  echo "👉 Essayez : sudo $0"
  exit 1
fi

# Mise à jour du système
echo "🔄 Mise à jour du système..."
apt update -y && apt upgrade -y

# Installation des dépendances
echo "📦 Installation des dépendances..."
apt install -y ca-certificates curl gnupg lsb-release

# Ajout de la clé GPG officielle Docker
echo "🔑 Ajout de la clé GPG Docker..."
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Ajout du dépôt Docker
echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
| tee /etc/apt/sources.list.d/docker.list > /dev/null

# Mise à jour après ajout du dépôt
apt update -y

# Installation de Docker Engine
echo "⬇️ Installation de Docker Engine..."
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Ajouter l’utilisateur actuel au groupe docker pour exécuter docker sans sudo
echo "👤 Ajout de l'utilisateur $(whoami) au groupe docker..."
usermod -aG docker $SUDO_USER

# Vérification de l’installation
echo "✅ Vérification de Docker et Docker Compose..."
docker --version
docker compose version

echo "🎉 Docker et Docker Compose ont été installés avec succès !"
echo "👉 Déconnectez-vous et reconnectez-vous pour utiliser docker sans sudo."
