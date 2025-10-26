#!/usr/bin/env bash

# Arrêt en cas d'erreur
set -e

echo "🚀 Installation de kubectl sur Pop!_OS..."

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
apt install -y curl apt-transport-https ca-certificates gnupg lsb-release

# Télécharger la dernière version stable de kubectl
echo "⬇️ Téléchargement de kubectl..."
KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"

# Vérification du téléchargement
if [[ ! -f kubectl ]]; then
  echo "❌ Échec du téléchargement de kubectl"
  exit 1
fi

# Rendre kubectl exécutable
chmod +x kubectl

# Déplacer kubectl dans /usr/local/bin
mv kubectl /usr/local/bin/

# Vérification de l'installation
echo "✅ Vérification..."
kubectl version --client --short

echo "🎉 kubectl a été installé avec succès sur Pop!_OS."
