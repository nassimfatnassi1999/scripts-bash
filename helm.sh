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

# Téléchargement et installation directe depuis GitHub (méthode officielle)
echo "⬇️ Téléchargement et installation de Helm depuis GitHub..."
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Vérification de l'installation
echo "✅ Vérification..."
helm version --short || { echo "❌ Échec de l'installation de Helm."; exit 1; }

echo "🎉 Helm a été installé avec succès sur Pop!_OS."

