#!/bin/bash

set -e

echo "🔄 Mise à jour du système..."
sudo apt update && sudo apt upgrade -y

echo "📦 Installation des dépendances système..."
sudo apt install -y curl wget git build-essential software-properties-common

########################################
# INSTALLATION DE VS CODE
########################################
echo "🧠 Installation de Visual Studio Code..."

wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
sudo install -o root -g root -m 644 packages.microsoft.gpg /usr/share/keyrings/
sudo sh -c 'echo "deb [arch=amd64 signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
rm -f packages.microsoft.gpg

sudo apt update
sudo apt install -y code

########################################
# INSTALLATION DE NVM
########################################
echo "📦 Installation de NVM..."

curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash

export NVM_DIR="$HOME/.nvm"
source "$NVM_DIR/nvm.sh"

########################################
# INSTALLATION NODE LTS
########################################
echo "🟢 Installation Node.js (LTS)..."

nvm install --lts
nvm use --lts
nvm alias default lts/*

########################################
# VÉRIFICATION
########################################
echo "✅ Version Node : $(node -v)"
echo "✅ Version NPM  : $(npm -v)"

########################################
# INSTALLATION REACT 18 (VITE)
########################################
echo "⚛️ Création projet React 18 avec Vite..."

npm create vite@latest my-react-app -- --template react
cd my-react-app
npm install

echo "📦 Installation explicite React 18..."
npm install react@18 react-dom@18

########################################
# INSTALLATION EXTENSION ANTIGRAVITY
########################################
echo "🧩 Installation extension Antigravity dans VS Code..."

code --install-extension antigravity.antigravity

########################################
# FIN
########################################
echo ""
echo "🎉 Installation terminée !"
echo "➡️ Pour lancer le projet React :"
echo "   cd my-react-app"
echo "   npm run dev"

