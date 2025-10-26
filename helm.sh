#!/usr/bin/env bash

# Arrêt en cas d'erreur
set -e

echo "🚀 Installation de Helm sur Pop!_OS..."

# Vérification des privilèges
if [[ $EUID -ne 0 ]]; then
  echo "❌ Ce script doit être exécuté avec sudo."
  echo "👉 Essayez : sudo $0"
  exit 1
fi

# Mise à jour du système
echo "🔄 Mise à jour du système..."
apt update -y && apt upgrade -y

# Installation des dépendances nécessaires
echo "📦 Installation des dépendances..."
apt install -y curl apt-transport-https gnupg lsb-release

# Ajouter le dépôt Helm officiel
echo "🗂️ Ajout du dépôt Helm..."
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor > /usr/share/keyrings/helm.gpg
echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | tee /etc/apt/sources.list.d/helm-stable-debian.list

# Mise à jour après ajout du dépôt
apt update -y

# Installation de Helm
echo "⬇️ Installation de Helm..."
apt install -y helm

# Vérification de l'installation
echo "✅ Vérification..."
helm version --short

echo "🎉 Helm a été installé avec succès sur Pop!_OS."
