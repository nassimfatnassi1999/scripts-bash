#!/usr/bin/env bash
# scripts/vm-tools.sh — VM guest tools installer and diagnostics
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
register_cleanup

SCRIPT_NAME="VM Tools Manager"
SCRIPT_DESC="Detect virtualization and install common guest tools"

handle_standard_args "$@"

detect_virtualization() {
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    systemd-detect-virt || true
  elif command -v virt-what >/dev/null 2>&1; then
    virt-what || true
  else
    log_warn "No virtualization detector installed."
    grep -Ei 'hypervisor|vmware|virtualbox|kvm|qemu' /proc/cpuinfo | head -5 || true
  fi
}

install_vmware_tools() {
  check_sudo
  detect_package_manager
  case "$PKG_MANAGER" in
    apt) run_cmd_sudo apt-get update -y; run_cmd_sudo apt-get install -y open-vm-tools open-vm-tools-desktop ;;
    dnf|yum) run_cmd_sudo "$PKG_MANAGER" install -y open-vm-tools open-vm-tools-desktop || run_cmd_sudo "$PKG_MANAGER" install -y open-vm-tools ;;
    pacman) run_cmd_sudo pacman -S --noconfirm open-vm-tools ;;
    zypper) run_cmd_sudo zypper install -y open-vm-tools ;;
    apk) run_cmd_sudo apk add open-vm-tools ;;
    *) log_error "Unsupported package manager."; return 1 ;;
  esac
}

install_virtualbox_tools() {
  check_sudo
  detect_package_manager
  case "$PKG_MANAGER" in
    apt) run_cmd_sudo apt-get update -y; run_cmd_sudo apt-get install -y virtualbox-guest-utils virtualbox-guest-x11 ;;
    dnf|yum) run_cmd_sudo "$PKG_MANAGER" install -y virtualbox-guest-additions ;;
    pacman) run_cmd_sudo pacman -S --noconfirm virtualbox-guest-utils ;;
    zypper) run_cmd_sudo zypper install -y virtualbox-guest-tools ;;
    apk) run_cmd_sudo apk add virtualbox-guest-additions ;;
    *) log_error "Unsupported package manager."; return 1 ;;
  esac
}

install_qemu_guest_agent() {
  check_sudo
  detect_package_manager
  case "$PKG_MANAGER" in
    apt) run_cmd_sudo apt-get update -y; run_cmd_sudo apt-get install -y qemu-guest-agent spice-vdagent ;;
    dnf|yum) run_cmd_sudo "$PKG_MANAGER" install -y qemu-guest-agent spice-vdagent ;;
    pacman) run_cmd_sudo pacman -S --noconfirm qemu-guest-agent spice-vdagent ;;
    zypper) run_cmd_sudo zypper install -y qemu-guest-agent spice-vdagent ;;
    apk) run_cmd_sudo apk add qemu-guest-agent spice-vdagent ;;
    *) log_error "Unsupported package manager."; return 1 ;;
  esac
}

enable_vm_services() {
  check_sudo
  if ! systemd_available; then log_warn "systemd not available."; return 0; fi
  for svc in vmtoolsd vboxservice qemu-guest-agent spice-vdagentd; do
    if systemctl list-unit-files "${svc}.service" >/dev/null 2>&1; then
      run_cmd_sudo systemctl enable --now "$svc" || true
    fi
  done
}

show_vm_status() {
  log_info "Virtualization:"
  detect_virtualization
  echo
  log_info "Relevant services:"
  if systemd_available; then
    systemctl status vmtoolsd vboxservice qemu-guest-agent spice-vdagentd --no-pager -l 2>/dev/null || true
  fi
  echo
  lsmod 2>/dev/null | grep -E 'vmw|vbox|virtio|qxl' || true
}

main_menu_choice() {
  menu_select "$SCRIPT_NAME" "Exit" \
    "1:Detect virtualization" \
    "2:Show VM status" \
    "3:Install VMware guest tools" \
    "4:Install VirtualBox guest tools" \
    "5:Install QEMU/KVM guest agent" \
    "6:Enable VM services" \
    "e:Show environment info"
}

main() {
  while true; do
    print_script_header "$SCRIPT_NAME" "$SCRIPT_DESC"
    main_menu_choice
    echo
    case "${REPLY:-}" in
      1) detect_virtualization || true; pause ;;
      2) show_vm_status || true; pause ;;
      3) install_vmware_tools || true; pause ;;
      4) install_virtualbox_tools || true; pause ;;
      5) install_qemu_guest_agent || true; pause ;;
      6) enable_vm_services || true; pause ;;
      e|E) show_env_info; pause ;;
      0) log_info "Bye!"; exit 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

main "$@"
