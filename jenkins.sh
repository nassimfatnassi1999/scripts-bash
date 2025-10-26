#!/usr/bin/env bash

# Arrêt en cas d'erreur
set -e

echo "🚀 Installation de Jenkins sur Pop!_OS..."

# Vérification des privilèges
if [[ $EUID -ne 0 ]]; then
  echo "❌ Ce script doit être exécuté avec les privilèges administrateur (sudo)."
  echo "👉 Essayez : sudo $0"
  exit 1
fi

# Mise à jour du système
echo "🔄 Mise à jour du système..."
apt update -y && apt upgrade -y

# Installation des dépendances Java et outils
echo "📦 Installation de Java et dépendances..."
apt install -y openjdk-17-jdk curl gnupg lsb-release

# Ajout de la clé GPG de Jenkins
echo "🔑 Ajout de la clé GPG Jenkins..."
curl -fsSL https://pkg.jenkins.io/debian/jenkins.io-2023.key | tee \
  /usr/share/keyrings/jenkins-keyring.asc > /dev/null

# Ajout du dépôt officiel Jenkins
echo "🗂️ Ajout du dépôt Jenkins..."
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
https://pkg.jenkins.io/debian binary/" | tee /etc/apt/sources.list.d/jenkins.list > /dev/null

# Mise à jour et installation
echo "⬇️ Installation de Jenkins..."
apt update -y
apt install -y jenkins

# Activation et démarrage du service
echo "⚙️ Démarrage du service Jenkins..."
systemctl enable jenkins
systemctl start jenkins

# Vérification du statut
systemctl status jenkins --no-pager

# Affichage du mot de passe initial
echo "🔐 Mot de passe initial Jenkins :"
cat /var/lib/jenkins/secrets/initialAdminPassword

echo "🎉 Jenkins a été installé et lancé avec succès !"
echo "🌐 Accédez à Jenkins via : http://localhost:8080"
