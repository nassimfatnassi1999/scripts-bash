#!/usr/bin/env bash
# scripts/secrets-manager.sh — Local secrets helper
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
register_cleanup

SCRIPT_NAME="Secrets Manager"
SCRIPT_DESC="Generate secrets, encrypt/decrypt files, inspect env files safely"

handle_standard_args "$@"

SECRETS_DIR="${SECRETS_DIR:-${HOME}/.local/share/devops-secrets}"

ensure_secrets_dir() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    log_info "[DRY-RUN] Would create secrets directory: $SECRETS_DIR"
  else
    mkdir -p "$SECRETS_DIR"
    chmod 700 "$SECRETS_DIR"
  fi
}

install_secret_tools() {
  check_sudo
  detect_package_manager
  case "$PKG_MANAGER" in
    apt) run_cmd_sudo apt-get update -y; run_cmd_sudo apt-get install -y openssl gnupg pass pwgen ;;
    dnf|yum) run_cmd_sudo "$PKG_MANAGER" install -y openssl gnupg2 pass pwgen ;;
    pacman) run_cmd_sudo pacman -S --noconfirm openssl gnupg pass pwgen ;;
    zypper) run_cmd_sudo zypper install -y openssl gpg2 password-store pwgen ;;
    apk) run_cmd_sudo apk add openssl gnupg pass pwgen ;;
    *) log_error "Unsupported package manager."; return 1 ;;
  esac
}

generate_password() {
  local length
  length="$(ask_input "Password length" "32")"
  [[ "$length" =~ ^[0-9]+$ ]] || { log_error "Invalid length."; return 1; }
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 "$(( length * 2 ))" | tr -dc 'A-Za-z0-9_@%+=:,./-' | head -c "$length"
    echo
  elif command -v pwgen >/dev/null 2>&1; then
    pwgen -s "$length" 1
  else
    log_error "Install openssl or pwgen first."
    return 1
  fi
}

generate_token_hex() {
  local bytes
  bytes="$(ask_input "Random bytes" "32")"
  [[ "$bytes" =~ ^[0-9]+$ ]] || { log_error "Invalid byte count."; return 1; }
  require_command openssl
  openssl rand -hex "$bytes"
}

encrypt_file() {
  require_command gpg
  local src dest
  src="$(ask_input "File to encrypt")"
  require_not_empty "$src" "Source file"
  [[ -f "$src" ]] || { log_error "File not found: $src"; return 1; }
  dest="$(ask_input "Encrypted output" "${src}.gpg")"
  if [[ -e "$dest" ]] && ! ask_confirm "Overwrite '$dest'?"; then return 0; fi
  run_cmd gpg --symmetric --cipher-algo AES256 -o "$dest" "$src"
  [[ "${DRY_RUN:-0}" == "1" ]] || chmod 600 "$dest"
  log_ok "Encrypted file written: $dest"
}

decrypt_file() {
  require_command gpg
  local src dest
  src="$(ask_input "Encrypted .gpg file")"
  require_not_empty "$src" "Encrypted file"
  [[ -f "$src" ]] || { log_error "File not found: $src"; return 1; }
  dest="$(ask_input "Decrypted output" "${src%.gpg}")"
  if [[ -e "$dest" ]] && ! ask_confirm "Overwrite '$dest'?"; then return 0; fi
  run_cmd gpg -o "$dest" -d "$src"
  [[ "${DRY_RUN:-0}" == "1" ]] || chmod 600 "$dest"
  log_ok "Decrypted file written: $dest"
}

create_secret_file() {
  ensure_secrets_dir
  local name file value
  name="$(ask_input "Secret name")"
  require_not_empty "$name" "Secret name"
  file="${SECRETS_DIR}/${name}"
  if [[ -e "$file" ]] && ! ask_confirm "Overwrite secret '$name'?"; then return 0; fi
  value="$(ask_secret "Secret value")"
  require_not_empty "$value" "Secret value"
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    log_info "[DRY-RUN] Would write secret file: $file"
  else
    printf '%s\n' "$value" > "$file"
    chmod 600 "$file"
  fi
  log_ok "Secret stored: $file"
}

list_secret_files() {
  ensure_secrets_dir
  find "$SECRETS_DIR" -maxdepth 1 -type f -printf '%M %u %g %TY-%Tm-%Td %TH:%TM %p\n' 2>/dev/null | sort || true
}

delete_secret_file() {
  ensure_secrets_dir
  local file
  list_secret_files
  file="$(ask_input "Secret file path to delete")"
  require_not_empty "$file" "Secret file"
  [[ -f "$file" ]] || { log_error "File not found: $file"; return 1; }
  log_warn "This permanently deletes the local secret file."
  if ask_confirm "Delete '$file'?"; then
    run_cmd rm -f "$file"
    log_ok "Deleted: $file"
  fi
}

mask_env_file() {
  local file
  file="$(ask_input "Env file to inspect" ".env")"
  [[ -f "$file" ]] || { log_error "File not found: $file"; return 1; }
  awk -F= '
    /^[[:space:]]*#/ || NF < 2 { print; next }
    {
      key=$1
      val=$0
      sub(/^[^=]*=/, "", val)
      if (length(val) <= 4) masked="****"; else masked=substr(val,1,2) "****" substr(val,length(val)-1,2)
      print key "=" masked
    }
  ' "$file"
}

main_menu_choice() {
  menu_select "$SCRIPT_NAME" "Exit" \
    "1:Install secret tools" \
    "2:Generate password" \
    "3:Generate hex token" \
    "4:Encrypt file with GPG" \
    "5:Decrypt GPG file" \
    "6:Create local secret file" \
    "7:List local secret files" \
    "8:Delete local secret file" \
    "9:Mask and display env file" \
    "e:Show environment info"
}

main() {
  while true; do
    print_script_header "$SCRIPT_NAME" "$SCRIPT_DESC"
    log_info "Secrets directory: $SECRETS_DIR"
    main_menu_choice
    echo
    case "${REPLY:-}" in
      1) install_secret_tools || true; pause ;;
      2) generate_password || true; pause ;;
      3) generate_token_hex || true; pause ;;
      4) encrypt_file || true; pause ;;
      5) decrypt_file || true; pause ;;
      6) create_secret_file || true; pause ;;
      7) list_secret_files || true; pause ;;
      8) delete_secret_file || true; pause ;;
      9) mask_env_file || true; pause ;;
      e|E) show_env_info; pause ;;
      0) log_info "Bye!"; exit 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

main "$@"
