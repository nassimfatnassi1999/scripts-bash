#!/usr/bin/env bash

set -e

echo "🚀 Installation des CLI Cloud sur Pop!_OS"

# Vérification des privilèges
if [[ $EUID -ne 0 ]]; then
  echo "❌ Ce script doit être exécuté avec sudo."
  echo "👉 Essayez : sudo $0"
  exit 1
fi

# Menu interactif
echo "Choisis le cloud provider pour installer sa CLI :"
echo "1) Azure (az CLI)"
echo "2) AWS (aws CLI)"
echo "3) Google Cloud (gcloud SDK)"
read -p "Entrez le numéro correspondant : " choice

case $choice in
  1)
    echo "⬇️ Installation Azure CLI..."
    curl -sL https://aka.ms/InstallAzureCLIDeb | bash
    echo "✅ Azure CLI installé !"
    echo "🔑 Connectez-vous avec : az login"
    ;;
  2)
    echo "⬇️ Installation AWS CLI v2..."
    apt update -y
    apt install -y unzip curl
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
    rm -rf awscliv2.zip aws
    echo "✅ AWS CLI installé !"
    echo "🔑 Configurez votre compte : aws configure"
    ;;
  3)
    echo "⬇️ Installation Google Cloud SDK..."
    apt update -y
    apt install -y curl apt-transport-https ca-certificates gnupg
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor > /usr/share/keyrings/cloud.google.gpg
    apt update -y
    apt install -y google-cloud-sdk
    echo "✅ Google Cloud SDK installé !"
    echo "🔑 Connectez-vous avec : gcloud auth login"
    ;;
  *)
    echo "❌ Choix invalide"
    exit 1
    ;;
esac

echo "🎉 Installation terminée !"
