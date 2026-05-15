#!/usr/bin/env bash
# scripts/helm.sh — Helm package manager for Kubernetes
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
register_cleanup

SCRIPT_NAME="Helm Manager"
SCRIPT_DESC="Install Helm, manage repositories and charts"

handle_standard_args "$@"

# ---------------------------------------------------------------------------
# STATUS
# ---------------------------------------------------------------------------
show_helm_status() {
  echo
  if is_installed helm; then
    log_ok "Helm: $(helm version --short 2>/dev/null)"
  else
    log_warn "Helm: NOT installed"
  fi
  if is_installed kubectl && kubectl cluster-info >/dev/null 2>&1; then
    log_ok "Kubernetes cluster: reachable"
  else
    log_warn "Kubernetes cluster: NOT reachable (kubectl not configured)"
  fi
  echo
}

# ---------------------------------------------------------------------------
# INSTALL HELM
# ---------------------------------------------------------------------------
install_helm() {
  if is_installed helm; then
    log_ok "Helm already installed: $(helm version --short 2>/dev/null)"
    if ! ask_confirm "Reinstall / update Helm?"; then return 0; fi
  fi

  require_internet
  check_sudo
  detect_package_manager

  case "$PKG_MANAGER" in
    apt)
      log_step "Installing Helm via apt..."
      local tmpdir; tmpdir="$(make_tmpdir)"
      download_file "https://baltocdn.com/helm/signing.asc" "${tmpdir}/helm.asc"
      run_cmd_sudo mkdir -p /usr/share/keyrings
      run_cmd gpg --dearmor < "${tmpdir}/helm.asc" | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" \
        | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
      run_cmd_sudo apt-get update -y
      run_cmd_sudo apt-get install -y helm
      ;;
    dnf|yum)
      log_step "Installing Helm via rpm..."
      # shellcheck disable=SC2086
      run_cmd sudo $PKG_INSTALL helm 2>/dev/null || _install_helm_script
      ;;
    pacman)
      log_step "Installing Helm via pacman..."
      run_cmd_sudo pacman -S --noconfirm helm
      ;;
    zypper)
      log_step "Installing Helm via zypper..."
      run_cmd_sudo zypper install -y helm
      ;;
    *)
      _install_helm_script
      ;;
  esac

  log_ok "Helm installed: $(helm version --short 2>/dev/null)"
}

_install_helm_script() {
  log_step "Installing Helm via official install script..."
  local tmpdir; tmpdir="$(make_tmpdir)"
  download_file "https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3" "${tmpdir}/get-helm-3.sh"
  chmod +x "${tmpdir}/get-helm-3.sh"
  run_cmd bash "${tmpdir}/get-helm-3.sh"
}

# ---------------------------------------------------------------------------
# REPOSITORIES
# ---------------------------------------------------------------------------
manage_repos() {
  require_command helm "Install Helm first (option 1)"
  while true; do
    echo
    log_info "=== Helm Repository Manager ==="
    log_info "Current repositories:"
    helm repo list 2>/dev/null || echo "  (none)"
    echo
    echo "  1) Add repository"
    echo "  2) Remove repository"
    echo "  3) Update all repositories"
    echo "  4) Search charts in repos"
    echo "  0) Back"
    echo
    read -r -p "Choose: " c
    case "${c:-}" in
      1)
        local repo_name repo_url
        repo_name="$(ask_input "Repository name (e.g., stable)")"
        require_not_empty "$repo_name" "Repository name"
        repo_url="$(ask_input "Repository URL")"
        require_not_empty "$repo_url" "Repository URL"
        helm repo add "$repo_name" "$repo_url"
        helm repo update
        log_ok "Repository added: $repo_name"
        ;;
      2)
        local repo_name
        repo_name="$(ask_input "Repository name to remove")"
        require_not_empty "$repo_name" "Repository name"
        if ask_confirm "Remove repository '$repo_name'?"; then
          helm repo remove "$repo_name"
          log_ok "Repository removed: $repo_name"
        fi
        ;;
      3)
        log_step "Updating all repositories..."
        helm repo update
        log_ok "Repositories updated."
        ;;
      4)
        local keyword
        keyword="$(ask_input "Search keyword")"
        require_not_empty "$keyword" "Keyword"
        helm search repo "$keyword"
        ;;
      0) return 0 ;;
      *) log_warn "Invalid option." ;;
    esac
  done
}

add_common_repos() {
  require_command helm
  log_step "Adding common Helm repositories..."
  local repos=(
    "bitnami https://charts.bitnami.com/bitnami"
    "stable https://charts.helm.sh/stable"
    "ingress-nginx https://kubernetes.github.io/ingress-nginx"
    "cert-manager https://charts.jetstack.io"
    "prometheus-community https://prometheus-community.github.io/helm-charts"
    "grafana https://grafana.github.io/helm-charts"
  )
  for entry in "${repos[@]}"; do
    local name url
    name="${entry%% *}"
    url="${entry#* }"
    if helm repo list 2>/dev/null | grep -q "^${name}"; then
      log_info "Repository already exists: $name"
    else
      helm repo add "$name" "$url" && log_ok "Added: $name"
    fi
  done
  helm repo update
  log_ok "Common repositories added and updated."
}

# ---------------------------------------------------------------------------
# CHART OPERATIONS
# ---------------------------------------------------------------------------
list_charts() {
  require_command helm
  local repo
  repo="$(ask_input "Repository name (leave empty for all)")"
  if [[ -n "$repo" ]]; then
    helm search repo "$repo/"
  else
    helm search repo ""
  fi
}

install_chart() {
  require_command helm
  local release_name chart_name namespace
  release_name="$(ask_input "Release name")"
  require_not_empty "$release_name" "Release name"
  chart_name="$(ask_input "Chart name (e.g., bitnami/nginx)")"
  require_not_empty "$chart_name" "Chart name"
  namespace="$(ask_input "Namespace" "default")"

  local extra_args=""
  if ask_confirm "Create namespace if it doesn't exist?"; then
    extra_args="$extra_args --create-namespace"
  fi
  if ask_confirm "Specify a values file?"; then
    local values_file
    values_file="$(ask_input "Values file path")"
    [[ -f "$values_file" ]] && extra_args="$extra_args -f $values_file"
  fi
  if ask_confirm "Set specific values (--set key=value)?"; then
    local set_values
    set_values="$(ask_input "key=value pairs (comma-separated)")"
    [[ -n "$set_values" ]] && extra_args="$extra_args --set $set_values"
  fi
  if ask_confirm "Dry-run (--dry-run)?"; then
    extra_args="$extra_args --dry-run"
  fi

  log_step "Installing chart: $chart_name as $release_name in namespace $namespace"
  # shellcheck disable=SC2086
  run_cmd helm install "$release_name" "$chart_name" --namespace "$namespace" $extra_args
  log_ok "Chart installed."
}

list_releases() {
  require_command helm
  local namespace
  namespace="$(ask_input "Namespace (leave empty for all)" "")"
  if [[ -n "$namespace" ]]; then
    helm list -n "$namespace"
  else
    helm list -A
  fi
}

uninstall_release() {
  require_command helm
  list_releases || true
  echo
  local release namespace
  release="$(ask_input "Release name to uninstall")"
  require_not_empty "$release" "Release name"
  namespace="$(ask_input "Namespace" "default")"
  if ask_confirm "Uninstall release '$release' from namespace '$namespace'?"; then
    run_cmd helm uninstall "$release" -n "$namespace"
    log_ok "Release uninstalled: $release"
  fi
}

upgrade_release() {
  require_command helm
  local release chart namespace
  release="$(ask_input "Release name")"
  require_not_empty "$release" "Release name"
  chart="$(ask_input "Chart name (e.g., bitnami/nginx)")"
  require_not_empty "$chart" "Chart name"
  namespace="$(ask_input "Namespace" "default")"
  if ask_confirm "Dry-run first?"; then
    helm upgrade "$release" "$chart" -n "$namespace" --dry-run
  fi
  if ask_confirm "Proceed with upgrade?"; then
    run_cmd helm upgrade "$release" "$chart" -n "$namespace" --install
    log_ok "Release upgraded: $release"
  fi
}

# ---------------------------------------------------------------------------
# MENU
# ---------------------------------------------------------------------------
main() {
  while true; do
    print_script_header "$SCRIPT_NAME" "$SCRIPT_DESC"
    show_helm_status
    echo "  ${BOLD}${YELLOW}Installation${RESET}"
    echo "  ${CYAN}1)${RESET} Install Helm"
    print_menu_separator
    echo "  ${BOLD}${YELLOW}Repositories${RESET}"
    echo "  ${CYAN}2)${RESET} Manage repositories (add/remove/update)"
    echo "  ${CYAN}3)${RESET} Add common repositories (bitnami, ingress-nginx, etc.)"
    echo "  ${CYAN}4)${RESET} List / search charts"
    print_menu_separator
    echo "  ${BOLD}${YELLOW}Releases${RESET}"
    echo "  ${CYAN}5)${RESET} Install chart"
    echo "  ${CYAN}6)${RESET} List releases"
    echo "  ${CYAN}7)${RESET} Upgrade release"
    echo "  ${CYAN}8)${RESET} Uninstall release"
    print_menu_separator
    echo "  ${CYAN}e)${RESET} Show environment info"
    echo "  ${CYAN}0)${RESET} Exit"
    echo
    read -r -p "Choose: " c
    echo
    case "${c:-}" in
      1) install_helm || true; pause ;;
      2) manage_repos || true; pause ;;
      3) add_common_repos || true; pause ;;
      4) list_charts || true; pause ;;
      5) install_chart || true; pause ;;
      6) list_releases || true; pause ;;
      7) upgrade_release || true; pause ;;
      8) uninstall_release || true; pause ;;
      e|E) show_env_info; pause ;;
      0) log_info "Bye!"; exit 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

main "$@"
