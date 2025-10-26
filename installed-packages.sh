#!/bin/bash
# Script to show the last installation commands and packages installed
# Works with apt, dpkg, snap, and flatpak

echo "🔍 Checking system installation history..."
echo "---------------------------------------------------------------"

# Function to format section headers
function header() {
  echo
  echo "🧩 $1"
  echo "---------------------------------------------------------------"
}

# --- APT HISTORY ---
if [ -f /var/log/apt/history.log ]; then
  header "APT packages installed recently (via apt-get / apt)"
  sudo zgrep -h "Install:" /var/log/apt/history.log* 2>/dev/null | tail -n 20
else
  echo "⚠️  No apt history found."
fi

# --- DPKG LOGS ---
if [ -f /var/log/dpkg.log ]; then
  header "DPKG packages installed recently (low-level installs)"
  sudo zgrep -h "install " /var/log/dpkg.log* 2>/dev/null | tail -n 20
else
  echo "⚠️  No dpkg logs found."
fi

# --- SNAP INSTALLATIONS ---
if command -v snap >/dev/null 2>&1; then
  header "Snap packages installed"
  snap changes | grep "Install" | tail -n 10
else
  echo "⚠️  Snap not installed on this system."
fi

# --- FLATPAK INSTALLATIONS ---
if command -v flatpak >/dev/null 2>&1; then
  header "Flatpak packages installed"
  flatpak history | grep install | tail -n 10
else
  echo "⚠️  Flatpak not installed on this system."
fi

# --- SHELL HISTORY (APT COMMANDS) ---
header "APT commands from your shell history"
grep -E "sudo apt|apt install|apt-get install" ~/.bash_history 2>/dev/null | tail -n 15

echo
echo "🟢 Done. These are the most recent installation actions on your system."
