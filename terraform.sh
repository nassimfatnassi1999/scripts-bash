#!/usr/bin/env bash

# Arrêt en cas d'erreur
set -e

echo "🚀 Installation de Terraform sur Pop!_OS..."

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
apt install -y gnupg software-properties-common curl

# Ajout de la clé GPG de HashiCorp
echo "🔑 Ajout de la clé GPG HashiCorp..."
curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

# Ajout du dépôt officiel HashiCorp
echo "🗂️ Ajout du dépôt HashiCorp..."
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list

# Mise à jour après ajout du dépôt
apt update -y

# Installation de Terraform
echo "⬇️ Installation de Terraform..."
apt install -y terraform

# Vérification de l'installation
echo "✅ Vérification..."
terraform -version

echo "🎉 Terraform a été installé avec succès sur Pop!_OS."
