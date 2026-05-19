#!/usr/bin/env bash
# scripts/minikube.sh — Minikube local Kubernetes manager
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
register_cleanup

SCRIPT_NAME="Minikube Manager"
SCRIPT_DESC="Install and manage Minikube for local Kubernetes development"

handle_standard_args "$@"

# ---------------------------------------------------------------------------
# STATUS
# ---------------------------------------------------------------------------
show_minikube_status() {
  echo
  if is_installed minikube; then
    log_ok "Minikube: $(minikube version --short 2>/dev/null || minikube version 2>/dev/null | head -1)"
    local status
    status="$(minikube status 2>/dev/null | head -5 || echo "Not started")"
    echo "$status"
  else
    log_warn "Minikube: NOT installed"
  fi
  echo
  # Detect available drivers
  local drivers=()
  is_installed docker     && drivers+=("docker")
  is_installed podman     && drivers+=("podman")
  is_installed kvm2       && drivers+=("kvm2")
  is_installed virtualbox && drivers+=("virtualbox")
  [[ ${#drivers[@]} -gt 0 ]] && log_info "Available drivers: ${drivers[*]}" || log_warn "No hypervisor/driver found."
  echo
}

# ---------------------------------------------------------------------------
# INSTALL
# ---------------------------------------------------------------------------
install_minikube() {
  if is_installed minikube; then
    log_ok "Minikube already installed: $(minikube version --short 2>/dev/null || true)"
    if ! ask_confirm "Reinstall / update Minikube?"; then return 0; fi
  fi

  require_internet
  check_sudo || return 1
  detect_package_manager || return 1

  local arch
  arch="$(get_arch_suffix)"
  local tmpdir; tmpdir="$(make_tmpdir)"

  case "$PKG_MANAGER" in
    apt)
      log_step "Downloading Minikube .deb package..."
      download_file "https://storage.googleapis.com/minikube/releases/latest/minikube_latest_${arch}.deb" \
        "${tmpdir}/minikube.deb"
      run_cmd_sudo dpkg -i "${tmpdir}/minikube.deb"
      ;;
    dnf|yum)
      log_step "Downloading Minikube .rpm package..."
      download_file "https://storage.googleapis.com/minikube/releases/latest/minikube-latest.${arch}.rpm" \
        "${tmpdir}/minikube.rpm"
      # shellcheck disable=SC2086
      run_cmd sudo $PKG_INSTALL "${tmpdir}/minikube.rpm"
      ;;
    pacman)
      if is_installed yay; then
        run_cmd yay -S --noconfirm minikube
      else
        _install_minikube_binary "$arch" "$tmpdir"
      fi
      ;;
    *)
      _install_minikube_binary "$arch" "$tmpdir"
      ;;
  esac

  log_ok "Minikube installed: $(minikube version --short 2>/dev/null || true)"
}

_install_minikube_binary() {
  local arch="$1"
  local tmpdir="$2"
  log_step "Downloading Minikube binary..."
  download_file "https://storage.googleapis.com/minikube/releases/latest/minikube-linux-${arch}" \
    "${tmpdir}/minikube"
  run_cmd_sudo install -m 755 "${tmpdir}/minikube" /usr/local/bin/minikube
}

# ---------------------------------------------------------------------------
# CLUSTER LIFECYCLE
# ---------------------------------------------------------------------------
detect_best_driver() {
  if is_installed docker && docker info >/dev/null 2>&1; then
    echo "docker"
  elif is_installed podman; then
    echo "podman"
  elif is_installed kvm2; then
    echo "kvm2"
  elif is_installed virtualbox; then
    echo "virtualbox"
  else
    echo "none"
  fi
}

start_minikube() {
  require_command minikube

  local best_driver
  best_driver="$(detect_best_driver)"

  local driver
  if [[ "$best_driver" == "none" ]]; then
    driver="$(ask_input "Driver (docker/podman/kvm2/virtualbox/none)" "none")"
  else
    driver="$(ask_input "Driver" "$best_driver")"
  fi

  local cpus memory k8s_version
  cpus="$(ask_input "CPUs" "2")"
  memory="$(ask_input "Memory (MB)" "2048")"
  k8s_version="$(ask_input "Kubernetes version (leave empty for latest)" "")"

  local args=("start" "--driver=${driver}" "--cpus=${cpus}" "--memory=${memory}")
  [[ -n "$k8s_version" ]] && args+=("--kubernetes-version=${k8s_version}")

  if ask_confirm "Also install addons (ingress, dashboard, metrics-server)?"; then
    args+=("--addons=ingress,dashboard,metrics-server")
  fi

  log_step "Starting Minikube with driver: $driver"
  run_cmd minikube "${args[@]}"
  log_ok "Minikube started!"
  log_info "Run 'kubectl cluster-info' to verify."
}

stop_minikube() {
  require_command minikube
  log_step "Stopping Minikube..."
  run_cmd minikube stop
  log_ok "Minikube stopped."
}

delete_minikube() {
  require_command minikube
  log_warn "This will delete the Minikube cluster and all data."
  if ask_confirm "Delete Minikube cluster?"; then
    if ask_confirm "Second confirmation: really delete?"; then
      run_cmd minikube delete
      log_ok "Minikube deleted."
    fi
  fi
}

status_minikube() {
  require_command minikube
  minikube status
}

pause_minikube() {
  require_command minikube
  run_cmd minikube pause
  log_ok "Minikube paused."
}

unpause_minikube() {
  require_command minikube
  run_cmd minikube unpause
  log_ok "Minikube unpaused."
}

# ---------------------------------------------------------------------------
# ADDONS
# ---------------------------------------------------------------------------
manage_addons() {
  require_command minikube
  while true; do
    echo
    log_info "=== Minikube Addons ==="
    minikube addons list
    echo
    echo "  1) Enable addon"
    echo "  2) Disable addon"
    echo "  0) Back"
    echo
    read -r -p "Choose: " c
    case "${c:-}" in
      1)
        local addon
        addon="$(ask_input "Addon name (e.g., ingress, dashboard, metrics-server)")"
        minikube addons enable "$addon"
        log_ok "Addon enabled: $addon"
        ;;
      2)
        local addon
        addon="$(ask_input "Addon name to disable")"
        minikube addons disable "$addon"
        log_ok "Addon disabled: $addon"
        ;;
      0) return 0 ;;
      *) log_warn "Invalid option." ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# DASHBOARD & TOOLS
# ---------------------------------------------------------------------------
open_dashboard() {
  require_command minikube
  log_step "Opening Minikube dashboard..."
  log_info "Press Ctrl+C to close."
  minikube dashboard || true
}

tunnel_minikube() {
  require_command minikube
  check_sudo || return 1
  log_step "Starting Minikube tunnel (requires sudo)..."
  log_info "Press Ctrl+C to stop."
  sudo minikube tunnel || true
}

# ---------------------------------------------------------------------------
# MENU
# ---------------------------------------------------------------------------
main() {
  while true; do
    print_script_header "$SCRIPT_NAME" "$SCRIPT_DESC"
    show_minikube_status
    echo "  ${BOLD}${YELLOW}Installation${RESET}"
    echo "  ${CYAN}1)${RESET} Install Minikube"
    print_menu_separator
    echo "  ${BOLD}${YELLOW}Cluster Lifecycle${RESET}"
    echo "  ${CYAN}2)${RESET} Start Minikube"
    echo "  ${CYAN}3)${RESET} Stop Minikube"
    echo "  ${CYAN}4)${RESET} Pause Minikube"
    echo "  ${CYAN}5)${RESET} Unpause Minikube"
    echo "  ${CYAN}6)${RESET} Status"
    echo "  ${CYAN}7)${RESET} Delete Minikube cluster"
    print_menu_separator
    echo "  ${BOLD}${YELLOW}Tools & Addons${RESET}"
    echo "  ${CYAN}8)${RESET} Manage addons"
    echo "  ${CYAN}9)${RESET} Open dashboard"
    echo "  ${CYAN}10)${RESET} Start tunnel (for LoadBalancer services)"
    print_menu_separator
    echo "  ${CYAN}e)${RESET}  Show environment info"
    echo "  ${CYAN}0)${RESET}  Exit"
    echo
    read -r -p "Choose: " c
    echo
    case "${c:-}" in
      1)  install_minikube || true; pause ;;
      2)  start_minikube || true; pause ;;
      3)  stop_minikube || true; pause ;;
      4)  pause_minikube || true; pause ;;
      5)  unpause_minikube || true; pause ;;
      6)  status_minikube || true; pause ;;
      7)  delete_minikube || true; pause ;;
      8)  manage_addons || true; pause ;;
      9)  open_dashboard || true; pause ;;
      10) tunnel_minikube || true; pause ;;
      e|E) show_env_info; pause ;;
      0) log_info "Bye!"; exit 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

main "$@"
