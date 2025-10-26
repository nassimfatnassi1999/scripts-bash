#!/usr/bin/env bash

# Arrêt en cas d'erreur
set -e

echo "🚀 Installation de HashiCorp Vault sur Pop!_OS..."

# Vérification des privilèges
if [[ $EUID -ne 0 ]]; then
  echo "❌ Ce script doit être exécuté avec les privilèges administrateur (sudo)."
  echo "👉 Essayez : sudo $0"
  exit 1
fi

# Mise à jour du système
echo "🔄 Mise à jour du système..."
apt update -y && apt upgrade -y

# Installation des dépendances
echo "📦 Installation des dépendances..."
apt install -y gnupg software-properties-common curl

# Ajout de la clé GPG HashiCorp
echo "🔑 Ajout de la clé GPG HashiCorp..."
curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

# Ajout du dépôt officiel
echo "🗂️ Ajout du dépôt HashiCorp..."
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list

# Mise à jour et installation
apt update -y
echo "⬇️ Installation de Vault..."
apt install -y vault

# Vérification
echo "✅ Vérification..."
vault --version

echo "🎉 Vault a été installé avec succès sur Pop!_OS."
