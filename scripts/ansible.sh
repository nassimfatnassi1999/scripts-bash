#!/usr/bin/env bash
# scripts/ansible.sh — Ansible installation and management
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
register_cleanup

SCRIPT_NAME="Ansible Manager"
SCRIPT_DESC="Install Ansible, manage inventory, run playbooks"

handle_standard_args "$@"

# ---------------------------------------------------------------------------
# CHECKS
# ---------------------------------------------------------------------------
check_ansible() {
  is_installed ansible && return 0 || return 1
}

# ---------------------------------------------------------------------------
# INSTALL
# ---------------------------------------------------------------------------
install_ansible() {
  if check_ansible; then
    log_ok "Ansible is already installed: $(ansible --version | head -1)"
    if ! ask_confirm "Reinstall / update anyway?"; then return 0; fi
  fi

  require_internet
  detect_package_manager || return 1

  case "$PKG_MANAGER" in
    apt)
      check_sudo || return 1
      log_step "Installing Ansible via apt..."
      run_cmd_sudo apt-get update -y
      run_cmd_sudo apt-get install -y software-properties-common curl gpg
      # Try PPA for ubuntu-like, else use pip/pip3
      if [[ "$OS_ID" == "ubuntu" || "$OS_ID_LIKE" == *ubuntu* ]]; then
        if command -v add-apt-repository >/dev/null 2>&1; then
          run_cmd_sudo add-apt-repository --yes --update ppa:ansible/ansible
          run_cmd_sudo apt-get install -y ansible
        else
          log_warn "add-apt-repository not found, installing via pip..."
          _install_ansible_pip
        fi
      else
        run_cmd_sudo apt-get install -y ansible || _install_ansible_pip
      fi
      ;;
    dnf|yum)
      check_sudo || return 1
      log_step "Installing Ansible via ${PKG_MANAGER}..."
      # shellcheck disable=SC2086
      run_cmd sudo $PKG_INSTALL epel-release 2>/dev/null || true
      # shellcheck disable=SC2086
      run_cmd sudo $PKG_INSTALL ansible
      ;;
    pacman)
      check_sudo || return 1
      log_step "Installing Ansible via pacman..."
      run_cmd_sudo pacman -S --noconfirm ansible
      ;;
    zypper)
      check_sudo || return 1
      log_step "Installing Ansible via zypper..."
      run_cmd_sudo zypper install -y ansible
      ;;
    apk)
      check_sudo || return 1
      log_step "Installing Ansible via apk..."
      run_cmd_sudo apk add ansible
      ;;
    brew)
      log_step "Installing Ansible via Homebrew..."
      run_cmd brew install ansible
      ;;
    *)
      log_warn "Package manager not detected. Trying pip3..."
      _install_ansible_pip
      ;;
  esac

  log_ok "Ansible installed: $(ansible --version | head -1)"
}

_install_ansible_pip() {
  if command -v pip3 >/dev/null 2>&1; then
    run_cmd pip3 install --user ansible
  elif command -v pip >/dev/null 2>&1; then
    run_cmd pip install --user ansible
  else
    log_error "pip3/pip not found. Cannot install Ansible."
    return 1
  fi
}

# ---------------------------------------------------------------------------
# INVENTORY
# ---------------------------------------------------------------------------
manage_inventory() {
  echo
  log_info "=== Inventory Management ==="
  echo "  1) Create example inventory file"
  echo "  2) Show current inventory"
  echo "  3) Edit inventory file"
  echo "  0) Back"
  echo
  read -r -p "Choose: " c
  case "${c:-}" in
    1)
      local inv_file
      inv_file="$(ask_input "Inventory file path" "${HOME}/ansible_inventory")"
      if [[ -f "$inv_file" ]]; then
        if ! ask_confirm "File exists. Overwrite?"; then return 0; fi
        backup_file "$inv_file"
      fi
      cat > "$inv_file" <<'EOF'
# Ansible Inventory Example
# Edit this file to define your hosts

[webservers]
web01 ansible_host=192.168.1.10 ansible_user=ubuntu
web02 ansible_host=192.168.1.11 ansible_user=ubuntu

[dbservers]
db01 ansible_host=192.168.1.20 ansible_user=ubuntu

[all:vars]
ansible_python_interpreter=/usr/bin/python3
# ansible_ssh_private_key_file=~/.ssh/id_rsa
EOF
      log_ok "Inventory created: $inv_file"
      ;;
    2)
      local inv_file
      inv_file="$(ask_input "Inventory file path" "${HOME}/ansible_inventory")"
      if [[ ! -f "$inv_file" ]]; then
        log_warn "File not found: $inv_file"
        return 0
      fi
      echo
      cat "$inv_file"
      ;;
    3)
      local inv_file
      inv_file="$(ask_input "Inventory file path" "${HOME}/ansible_inventory")"
      local editor="${EDITOR:-nano}"
      "$editor" "$inv_file" || true
      ;;
    0) return 0 ;;
    *) log_warn "Invalid option." ;;
  esac
}

# ---------------------------------------------------------------------------
# PING
# ---------------------------------------------------------------------------
run_ping() {
  require_command ansible
  local inv_file
  inv_file="$(ask_input "Inventory file path" "${HOME}/ansible_inventory")"
  [[ ! -f "$inv_file" ]] && { log_error "Inventory not found: $inv_file"; return 1; }

  local target
  target="$(ask_input "Target host/group" "all")"

  log_step "Running ansible ping on: $target"
  run_cmd ansible -i "$inv_file" "$target" -m ping
}

# ---------------------------------------------------------------------------
# PLAYBOOK
# ---------------------------------------------------------------------------
run_playbook() {
  require_command ansible-playbook
  local inv_file
  inv_file="$(ask_input "Inventory file path" "${HOME}/ansible_inventory")"
  [[ ! -f "$inv_file" ]] && { log_error "Inventory not found: $inv_file"; return 1; }

  local pb_file
  pb_file="$(ask_input "Playbook file path")"
  require_not_empty "$pb_file" "Playbook path"
  [[ ! -f "$pb_file" ]] && { log_error "Playbook not found: $pb_file"; return 1; }

  local extra_args=""
  if ask_confirm "Run in check mode (dry-run)?"; then
    extra_args="--check"
  fi

  if ask_confirm "Add verbose output (-v)?"; then
    extra_args="$extra_args -v"
  fi

  local become_pass=""
  if ask_confirm "Use sudo on remote hosts (--ask-become-pass)?"; then
    extra_args="$extra_args --ask-become-pass"
  fi

  log_step "Running playbook: $pb_file"
  # shellcheck disable=SC2086
  run_cmd ansible-playbook -i "$inv_file" "$pb_file" $extra_args
}

# ---------------------------------------------------------------------------
# CONFIG
# ---------------------------------------------------------------------------
show_ansible_config() {
  require_command ansible
  ansible --version
  echo
  ansible-config dump --only-changed 2>/dev/null || ansible-config dump 2>/dev/null | head -20
}

create_example_playbook() {
  local pb_file
  pb_file="$(ask_input "Playbook file path" "${HOME}/example-playbook.yml")"
  if [[ -f "$pb_file" ]]; then
    if ! ask_confirm "File exists. Overwrite?"; then return 0; fi
    backup_file "$pb_file"
  fi
  cat > "$pb_file" <<'EOF'
---
- name: Example Playbook
  hosts: all
  become: true
  gather_facts: true

  vars:
    packages_to_install:
      - curl
      - wget
      - git

  tasks:
    - name: Update package cache (Debian/Ubuntu)
      ansible.builtin.apt:
        update_cache: true
      when: ansible_os_family == "Debian"

    - name: Install packages
      ansible.builtin.package:
        name: "{{ packages_to_install }}"
        state: present

    - name: Show OS info
      ansible.builtin.debug:
        msg: "Running on {{ ansible_distribution }} {{ ansible_distribution_version }}"
EOF
  log_ok "Example playbook created: $pb_file"
}

# ---------------------------------------------------------------------------
# MENU
# ---------------------------------------------------------------------------
show_status() {
  echo
  if check_ansible; then
    log_ok "Ansible: $(ansible --version | head -1)"
    log_ok "ansible-playbook: $(command -v ansible-playbook)"
  else
    log_warn "Ansible: NOT installed"
  fi
  echo
}

main() {
  while true; do
    print_script_header "$SCRIPT_NAME" "$SCRIPT_DESC"
    show_status
    echo "  ${CYAN}1)${RESET} Install Ansible"
    echo "  ${CYAN}2)${RESET} Show Ansible version/config"
    echo "  ${CYAN}3)${RESET} Manage inventory"
    echo "  ${CYAN}4)${RESET} Run ping (check host connectivity)"
    echo "  ${CYAN}5)${RESET} Run playbook"
    echo "  ${CYAN}6)${RESET} Create example playbook"
    echo "  ${CYAN}e)${RESET} Show environment info"
    print_menu_separator
    echo "  ${CYAN}0)${RESET} Exit"
    echo
    read -r -p "Choose: " c
    echo
    case "${c:-}" in
      1) install_ansible || true; pause ;;
      2) show_ansible_config || true; pause ;;
      3) manage_inventory || true; pause ;;
      4) run_ping || true; pause ;;
      5) run_playbook || true; pause ;;
      6) create_example_playbook || true; pause ;;
      e|E) show_env_info; pause ;;
      0) log_info "Bye!"; exit 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

main "$@"
