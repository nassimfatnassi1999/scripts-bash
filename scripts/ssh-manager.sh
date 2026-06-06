#!/usr/bin/env bash
# scripts/ssh-manager.sh — SSH client/server and key manager
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
register_cleanup

SCRIPT_NAME="SSH Manager"
SCRIPT_DESC="Manage SSH keys, config, agent, known_hosts and sshd"

handle_standard_args "$@"

SSH_DIR="${HOME}/.ssh"

install_ssh_tools() {
  detect_package_manager || return 1
  case "$PKG_MANAGER" in
    apt) check_sudo || return 1; run_cmd_sudo apt-get update -y; run_cmd_sudo apt-get install -y openssh-client openssh-server ;;
    dnf|yum) check_sudo || return 1; run_cmd_sudo "$PKG_MANAGER" install -y openssh-clients openssh-server ;;
    pacman) check_sudo || return 1; run_cmd_sudo pacman -S --noconfirm openssh ;;
    zypper) check_sudo || return 1; run_cmd_sudo zypper install -y openssh ;;
    apk) check_sudo || return 1; run_cmd_sudo apk add openssh-client openssh-server ;;
    brew) run_cmd brew install openssh ;;
    *) log_error "Unsupported package manager."; return 1 ;;
  esac
}

ensure_ssh_dir() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    log_info "[DRY-RUN] Would create ${SSH_DIR} with 700 permissions."
  else
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
  fi
}

list_keys() {
  ensure_ssh_dir
  log_info "SSH directory: $SSH_DIR"
  find "$SSH_DIR" -maxdepth 1 -type f \( -name '*.pub' -o -name 'id_*' \) -printf '%M %u %g %p\n' 2>/dev/null | sort || true
}

generate_key() {
  require_command ssh-keygen "Install OpenSSH client first."
  ensure_ssh_dir
  local type name comment bits
  menu_select "Key Type" "Cancel" "1:ed25519" "2:rsa"
  case "$REPLY" in
    1) type="ed25519" ;;
    2) type="rsa" ;;
    0) return 0 ;;
    *) log_warn "Invalid option."; return 1 ;;
  esac
  name="$(ask_input "Key file name" "id_${type}")"
  comment="$(ask_input "Key comment" "${USER}@$(hostname)")"
  local path="${SSH_DIR}/${name}"
  if [[ -e "$path" ]] && ! ask_confirm "Key exists. Overwrite '$path'?"; then return 0; fi
  if [[ "$type" == "rsa" ]]; then
    bits="$(ask_input "RSA bits" "4096")"
    run_cmd ssh-keygen -t rsa -b "$bits" -C "$comment" -f "$path"
  else
    run_cmd ssh-keygen -t ed25519 -C "$comment" -f "$path"
  fi
  [[ "${DRY_RUN:-0}" == "1" ]] || chmod 600 "$path"
  log_ok "Key generated: $path"
}

show_public_key() {
  local key
  list_keys
  key="$(ask_input "Private or public key path" "${SSH_DIR}/id_ed25519.pub")"
  [[ "$key" != *.pub ]] && key="${key}.pub"
  [[ -f "$key" ]] || { log_error "Public key not found: $key"; return 1; }
  cat "$key"
}

add_key_to_agent() {
  require_command ssh-add
  local key
  key="$(ask_input "Private key path" "${SSH_DIR}/id_ed25519")"
  [[ -f "$key" ]] || { log_error "Key not found: $key"; return 1; }
  if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
    log_warn "SSH_AUTH_SOCK is not set. Start an agent in your shell first:"
    echo "  eval \"\$(ssh-agent -s)\""
    return 1
  fi
  run_cmd ssh-add "$key"
}

scan_known_host() {
  require_command ssh-keyscan
  ensure_ssh_dir
  local host port known_hosts
  host="$(ask_input "Host")"
  port="$(ask_input "Port" "22")"
  require_not_empty "$host" "Host"
  known_hosts="${SSH_DIR}/known_hosts"
  if ask_confirm "Append host key for ${host}:${port} to known_hosts?"; then
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
      log_info "[DRY-RUN] Would append ssh-keyscan output to $known_hosts"
    else
      ssh-keyscan -p "$port" "$host" >> "$known_hosts"
      chmod 600 "$known_hosts"
    fi
    log_ok "known_hosts updated."
  fi
}

remove_known_host() {
  require_command ssh-keygen
  local host known_hosts
  host="$(ask_input "Host to remove from known_hosts")"
  require_not_empty "$host" "Host"
  known_hosts="${SSH_DIR}/known_hosts"
  [[ -f "$known_hosts" ]] || { log_warn "known_hosts not found."; return 0; }
  if ask_confirm "Remove '$host' from known_hosts?"; then
    run_cmd ssh-keygen -R "$host" -f "$known_hosts"
  fi
}

test_connection() {
  require_command ssh
  local target port
  target="$(ask_input "SSH target (user@host)")"
  port="$(ask_input "Port" "22")"
  require_not_empty "$target" "Target"
  run_cmd ssh -p "$port" -o BatchMode=yes -o ConnectTimeout=8 "$target" exit
}

edit_ssh_config() {
  ensure_ssh_dir
  local cfg="${SSH_DIR}/config"
  if [[ ! -f "$cfg" && "${DRY_RUN:-0}" != "1" ]]; then
    touch "$cfg"
    chmod 600 "$cfg"
  fi
  "${EDITOR:-nano}" "$cfg"
}

sshd_status() {
  if systemd_available; then
    systemctl status sshd --no-pager -l 2>/dev/null || systemctl status ssh --no-pager -l 2>/dev/null || true
  elif command -v rc-service >/dev/null 2>&1; then
    rc-service sshd status || true
  else
    log_warn "No supported service manager found."
  fi
}

restart_sshd() {
  check_sudo || return 1
  log_warn "Restarting SSH daemon can disconnect active remote sessions if config is invalid."
  if command -v sshd >/dev/null 2>&1; then
    run_cmd_sudo sshd -t
  fi
  if ! ask_confirm "Restart SSH daemon?"; then return 0; fi
  if systemd_available; then
    run_cmd_sudo systemctl restart sshd 2>/dev/null || run_cmd_sudo systemctl restart ssh
  elif command -v rc-service >/dev/null 2>&1; then
    run_cmd_sudo rc-service sshd restart
  else
    run_cmd_sudo service ssh restart 2>/dev/null || run_cmd_sudo service sshd restart
  fi
}

show_status() {
  echo
  if command -v ssh >/dev/null 2>&1; then log_ok "ssh: $(ssh -V 2>&1)"; else log_warn "ssh: missing"; fi
  if [[ -S "${SSH_AUTH_SOCK:-}" ]]; then log_ok "ssh-agent socket: $SSH_AUTH_SOCK"; else log_warn "ssh-agent socket not detected"; fi
  echo
}

main_menu_choice() {
  menu_select "$SCRIPT_NAME" "Exit" \
    "1:Install SSH tools" \
    "2:List keys" \
    "3:Generate SSH key" \
    "4:Show public key" \
    "5:Add key to ssh-agent" \
    "6:Scan host into known_hosts" \
    "7:Remove host from known_hosts" \
    "8:Test SSH connection" \
    "9:Edit SSH client config" \
    "10:Show SSH daemon status" \
    "11:Restart SSH daemon" \
    "e:Show environment info"
}

main() {
  while true; do
    print_script_header "$SCRIPT_NAME" "$SCRIPT_DESC"
    show_status
    main_menu_choice
    echo
    case "${REPLY:-}" in
      1) install_ssh_tools || true; pause ;;
      2) list_keys || true; pause ;;
      3) generate_key || true; pause ;;
      4) show_public_key || true; pause ;;
      5) add_key_to_agent || true; pause ;;
      6) scan_known_host || true; pause ;;
      7) remove_known_host || true; pause ;;
      8) test_connection || true; pause ;;
      9) edit_ssh_config || true; pause ;;
      10) sshd_status || true; pause ;;
      11) restart_sshd || true; pause ;;
      e|E) show_env_info; pause ;;
      0) log_info "Bye!"; exit 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

main "$@"
