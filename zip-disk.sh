#!/usr/bin/env bash
set -euo pipefail

# =========================
# Disk/Folder Zip Menu Tool
# =========================

# ---- Colors (no emoji for compatibility) ----
if command -v tput >/dev/null 2>&1; then
  BOLD="$(tput bold)"; RESET="$(tput sgr0)"
  RED="$(tput setaf 1)"; GREEN="$(tput setaf 2)"; YELLOW="$(tput setaf 3)"; CYAN="$(tput setaf 6)"
else
  BOLD=""; RESET=""
  RED=""; GREEN=""; YELLOW=""; CYAN=""
fi

ok()   { echo "${GREEN}${BOLD}[OK]${RESET} $*"; }
info() { echo "${CYAN}${BOLD}[i]${RESET} $*"; }
warn() { echo "${YELLOW}${BOLD}[!]${RESET} $*"; }
err()  { echo "${RED}${BOLD}[X]${RESET} $*" >&2; }

pause() { read -r -p "Press Enter to continue... " _; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || return 1
}

install_zip_popos() {
  # Pop!_OS / Ubuntu
  if ! need_cmd sudo; then
    err "sudo not found; install zip manually."
    return 1
  fi
  info "Installing zip..."
  sudo apt update -y
  sudo apt install -y zip
  ok "zip installed."
}

show_disks() {
  echo "=== List of disks and partitions ==="
  lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT
  echo
  echo "=== Total usage summary ==="
  df -h --total | awk 'NR==1 || $1=="total"{print}'
  echo
}

# ---- State ----
SOURCE_PATH="${SOURCE_PATH:-}"
DEST_ZIP="${DEST_ZIP:-}"

set_source() {
  show_disks
  read -r -p "Enter source mount point or directory path (e.g., /mnt/data or /home/$USER): " p
  if [[ -z "${p:-}" ]]; then
    err "Empty path."
    return 1
  fi
  if [[ ! -d "$p" ]]; then
    err "Path does not exist or is not a directory: $p"
    return 1
  fi
  SOURCE_PATH="$p"
  ok "Source set to: $SOURCE_PATH"
}

set_destination() {
  read -r -p "Enter destination .zip full path (e.g., /home/$USER/backup.zip): " z
  if [[ -z "${z:-}" ]]; then
    err "Empty destination."
    return 1
  fi

  # Ensure it ends with .zip (optional but helpful)
  if [[ "$z" != *.zip ]]; then
    warn "Destination does not end with .zip. Appending .zip"
    z="${z}.zip"
  fi

  # Check destination directory exists
  local dir
  dir="$(dirname "$z")"
  if [[ ! -d "$dir" ]]; then
    err "Destination directory does not exist: $dir"
    return 1
  fi

  # If file exists, ask before overwrite
  if [[ -e "$z" ]]; then
    read -r -p "File exists. Overwrite? (y/N): " ans
    if [[ "${ans:-}" != "y" && "${ans:-}" != "Y" ]]; then
      warn "Cancelled. Choose another destination."
      return 1
    fi
  fi

  DEST_ZIP="$z"
  ok "Destination set to: $DEST_ZIP"
}

show_current_config() {
  echo "=== Current configuration ==="
  echo "Source      : ${SOURCE_PATH:-<not set>}"
  echo "Destination : ${DEST_ZIP:-<not set>}"
  echo
}

compress_now() {
  if [[ -z "${SOURCE_PATH:-}" ]]; then
    err "Source not set. Choose option 2 first."
    return 1
  fi
  if [[ -z "${DEST_ZIP:-}" ]]; then
    err "Destination not set. Choose option 3 first."
    return 1
  fi

  if ! need_cmd zip; then
    warn "'zip' is not installed."
    read -r -p "Install zip now (Pop!_OS/Ubuntu apt)? (y/N): " ans
    if [[ "${ans:-}" == "y" || "${ans:-}" == "Y" ]]; then
      install_zip_popos || return 1
    else
      err "zip is required. Aborting."
      return 1
    fi
  fi

  info "Starting compression..."
  info "Source: $SOURCE_PATH"
  info "Dest  : $DEST_ZIP"
  echo

  # -r recursive, -q quiet, -y store symlinks as symlinks
  # Remove -q if you want to see files being added
  if zip -r -y "$DEST_ZIP" "$SOURCE_PATH"; then
    ok "Compression completed successfully."
    ls -lh "$DEST_ZIP" || true
  else
    err "Compression failed."
    return 1
  fi
}

# ---- Menu UI ----
print_header() {
  clear || true
  echo "${BOLD}==============================${RESET}"
  echo "${BOLD}   Disk/Folder ZIP Menu Tool  ${RESET}"
  echo "${BOLD}==============================${RESET}"
  echo
}

print_menu() {
  echo "${BOLD}1) Show disks/partitions + total usage${RESET}"
  echo "${BOLD}2) Set source (mount point/folder)${RESET}"
  echo "${BOLD}3) Set destination (.zip path)${RESET}"
  echo "${BOLD}4) Show current configuration${RESET}"
  echo "${BOLD}5) Compress now${RESET}"
  echo "${BOLD}0) Exit${RESET}"
  echo
}

main() {
  while true; do
    print_header
    print_menu
    read -r -p "Choose an option: " choice
    echo
    case "${choice:-}" in
      1) show_disks; pause ;;
      2) set_source || true; pause ;;
      3) set_destination || true; pause ;;
      4) show_current_config; pause ;;
      5) compress_now || true; pause ;;
      0) info "Bye."; exit 0 ;;
      *) warn "Invalid option."; pause ;;
    esac
  done
}

main