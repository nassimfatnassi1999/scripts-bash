#!/usr/bin/env bash

set -e

echo "🚀 Installation de Minikube sur Pop!_OS"

# Vérification des privilèges
if [[ $EUID -ne 0 ]]; then
  echo "❌ Ce script doit être exécuté avec sudo."
  echo "👉 Essayez : sudo $0"
  exit 1
fi

# Mise à jour du système
echo "🔄 Mise à jour du système..."
apt update -y && apt upgrade -y

# Installer les dépendances nécessaires
echo "📦 Installation des dépendances..."
apt install -y curl conntrack

# Télécharger le binaire Minikube
echo "⬇️ Téléchargement de Minikube..."
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64

# Rendre le binaire exécutable
chmod +x minikube-linux-amd64

# Déplacer le binaire dans /usr/local/bin
mv minikube-linux-amd64 /usr/local/bin/minikube

# Vérification de l'installation
echo "✅ Vérification..."
minikube version

echo "🎉 Minikube installé avec succès !"

# Optionnel : démarrage rapide avec Docker
if command -v docker &> /dev/null; then
  echo "💡 Vous pouvez démarrer Minikube avec Docker comme driver :"
  echo "minikube start --driver=docker"
else
  echo "⚠️ Docker n'est pas installé. Installez Docker pour utiliser Minikube avec le driver Docker."
fi
