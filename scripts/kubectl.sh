#!/usr/bin/env bash
# scripts/kubectl.sh — kubectl installer and Kubernetes cluster manager
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
register_cleanup

SCRIPT_NAME="kubectl Manager"
SCRIPT_DESC="Install kubectl and manage Kubernetes contexts, namespaces, and resources"

handle_standard_args "$@"

# ---------------------------------------------------------------------------
# STATUS
# ---------------------------------------------------------------------------
show_kubectl_status() {
  echo
  if is_installed kubectl; then
    log_ok "kubectl: $(kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null | head -1)"
    local ctx
    ctx="$(kubectl config current-context 2>/dev/null || echo 'none')"
    log_info "Current context: $ctx"
  else
    log_warn "kubectl: NOT installed"
  fi
  echo
}

# ---------------------------------------------------------------------------
# INSTALL
# ---------------------------------------------------------------------------
install_kubectl() {
  if is_installed kubectl; then
    log_ok "kubectl already installed: $(kubectl version --client --short 2>/dev/null || true)"
    if ! ask_confirm "Reinstall / update kubectl?"; then return 0; fi
  fi

  require_internet
  check_sudo
  detect_package_manager

  local install_method
  install_method="$(ask_input "Install method: 1=binary, 2=package manager" "1")"

  if [[ "$install_method" == "2" ]]; then
    _install_kubectl_pkg
  else
    _install_kubectl_binary
  fi

  log_ok "kubectl installed: $(kubectl version --client --short 2>/dev/null || true)"
}

_install_kubectl_binary() {
  log_step "Downloading kubectl binary..."
  local arch
  arch="$(get_arch_suffix)"
  local version
  version="$(curl -fsSL https://dl.k8s.io/release/stable.txt 2>/dev/null || echo "v1.29.0")"
  local tmpdir; tmpdir="$(make_tmpdir)"
  download_file "https://dl.k8s.io/release/${version}/bin/linux/${arch}/kubectl" "${tmpdir}/kubectl"
  run_cmd_sudo install -m 755 "${tmpdir}/kubectl" /usr/local/bin/kubectl
}

_install_kubectl_pkg() {
  detect_package_manager
  case "$PKG_MANAGER" in
    apt)
      run_cmd_sudo apt-get update -y
      run_cmd_sudo apt-get install -y ca-certificates curl gnupg
      run_cmd_sudo mkdir -p /etc/apt/keyrings
      local tmpdir; tmpdir="$(make_tmpdir)"
      download_file "https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key" "${tmpdir}/k8s.key"
      run_cmd_sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg < "${tmpdir}/k8s.key"
      echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" \
        | sudo tee /etc/apt/sources.list.d/kubernetes.list
      run_cmd_sudo apt-get update -y
      run_cmd_sudo apt-get install -y kubectl
      ;;
    dnf|yum)
      cat > /tmp/kubernetes.repo <<'EOF'
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/repodata/repomd.xml.key
EOF
      run_cmd_sudo mv /tmp/kubernetes.repo /etc/yum.repos.d/kubernetes.repo
      # shellcheck disable=SC2086
      run_cmd sudo $PKG_INSTALL kubectl
      ;;
    pacman)
      run_cmd_sudo pacman -S --noconfirm kubectl
      ;;
    *)
      _install_kubectl_binary
      ;;
  esac
}

# ---------------------------------------------------------------------------
# CONTEXT MANAGEMENT
# ---------------------------------------------------------------------------
list_contexts() {
  require_command kubectl
  log_info "Available contexts:"
  kubectl config get-contexts
}

switch_context() {
  require_command kubectl
  list_contexts
  echo
  local ctx
  ctx="$(ask_input "Context name to switch to")"
  require_not_empty "$ctx" "Context name"
  kubectl config use-context "$ctx"
  log_ok "Switched to context: $ctx"
}

show_current_context() {
  require_command kubectl
  local ctx
  ctx="$(kubectl config current-context 2>/dev/null || echo 'none')"
  log_info "Current context: $ctx"
  echo
  kubectl cluster-info 2>/dev/null || log_warn "Cannot connect to cluster."
}

# ---------------------------------------------------------------------------
# NAMESPACE MANAGEMENT
# ---------------------------------------------------------------------------
list_namespaces() {
  require_command kubectl
  kubectl get namespaces
}

create_namespace() {
  require_command kubectl
  local ns
  ns="$(ask_input "Namespace name to create")"
  require_not_empty "$ns" "Namespace name"
  if kubectl get namespace "$ns" >/dev/null 2>&1; then
    log_warn "Namespace already exists: $ns"
    return 0
  fi
  kubectl create namespace "$ns"
  log_ok "Namespace created: $ns"
}

set_default_namespace() {
  require_command kubectl
  list_namespaces
  echo
  local ns ctx
  ns="$(ask_input "Default namespace" "default")"
  ctx="$(kubectl config current-context 2>/dev/null)"
  kubectl config set-context "$ctx" --namespace="$ns"
  log_ok "Default namespace set to: $ns"
}

# ---------------------------------------------------------------------------
# RESOURCE INSPECTION
# ---------------------------------------------------------------------------
get_pods() {
  require_command kubectl
  local ns
  ns="$(ask_input "Namespace" "default")"
  kubectl get pods -n "$ns" -o wide
}

get_services() {
  require_command kubectl
  local ns
  ns="$(ask_input "Namespace" "default")"
  kubectl get services -n "$ns"
}

get_deployments() {
  require_command kubectl
  local ns
  ns="$(ask_input "Namespace" "default")"
  kubectl get deployments -n "$ns"
}

describe_resource() {
  require_command kubectl
  local resource_type resource_name namespace
  resource_type="$(ask_input "Resource type (pod/deployment/service/etc.)" "pod")"
  resource_name="$(ask_input "Resource name")"
  require_not_empty "$resource_name" "Resource name"
  namespace="$(ask_input "Namespace" "default")"
  kubectl describe "$resource_type" "$resource_name" -n "$namespace"
}

show_logs() {
  require_command kubectl
  local pod ns
  local pods
  pods="$(kubectl get pods --all-namespaces --no-headers 2>/dev/null | awk '{print $2" ("$1")"}' | head -20 || true)"
  [[ -n "$pods" ]] && echo "Available pods:" && echo "$pods" && echo
  pod="$(ask_input "Pod name")"
  require_not_empty "$pod" "Pod name"
  ns="$(ask_input "Namespace" "default")"
  local lines
  lines="$(ask_input "Number of lines" "100")"
  if ask_confirm "Follow logs? (Ctrl+C to stop)"; then
    kubectl logs -n "$ns" "$pod" -f --tail="$lines"
  else
    kubectl logs -n "$ns" "$pod" --tail="$lines"
  fi
}

delete_resource() {
  require_command kubectl
  local resource_type resource_name namespace
  resource_type="$(ask_input "Resource type")"
  resource_name="$(ask_input "Resource name")"
  require_not_empty "$resource_name" "Resource name"
  namespace="$(ask_input "Namespace" "default")"
  if ask_confirm "Delete $resource_type/$resource_name in namespace $namespace?"; then
    kubectl delete "$resource_type" "$resource_name" -n "$namespace"
    log_ok "Deleted: $resource_type/$resource_name"
  fi
}

apply_manifest() {
  require_command kubectl
  local manifest
  manifest="$(ask_input "Manifest file path or URL")"
  require_not_empty "$manifest" "Manifest"
  if ask_confirm "Dry-run first?"; then
    kubectl apply --dry-run=client -f "$manifest"
    echo
  fi
  if ask_confirm "Apply manifest?"; then
    kubectl apply -f "$manifest"
    log_ok "Manifest applied."
  fi
}

# ---------------------------------------------------------------------------
# QUICK OVERVIEW
# ---------------------------------------------------------------------------
cluster_overview() {
  require_command kubectl
  log_info "=== Cluster Overview ==="
  echo
  echo "--- Nodes ---"
  kubectl get nodes 2>/dev/null || log_warn "Cannot reach cluster."
  echo
  echo "--- Namespaces ---"
  kubectl get namespaces 2>/dev/null || true
  echo
  echo "--- All Pods (all namespaces) ---"
  kubectl get pods -A 2>/dev/null | head -30 || true
}

# ---------------------------------------------------------------------------
# MENU
# ---------------------------------------------------------------------------
main() {
  while true; do
    print_script_header "$SCRIPT_NAME" "$SCRIPT_DESC"
    show_kubectl_status
    echo "  ${BOLD}${YELLOW}Installation${RESET}"
    echo "  ${CYAN}1)${RESET}  Install kubectl"
    print_menu_separator
    echo "  ${BOLD}${YELLOW}Contexts & Clusters${RESET}"
    echo "  ${CYAN}2)${RESET}  List contexts"
    echo "  ${CYAN}3)${RESET}  Switch context"
    echo "  ${CYAN}4)${RESET}  Show current context / cluster info"
    echo "  ${CYAN}5)${RESET}  Cluster overview (nodes + pods)"
    print_menu_separator
    echo "  ${BOLD}${YELLOW}Namespaces${RESET}"
    echo "  ${CYAN}6)${RESET}  List namespaces"
    echo "  ${CYAN}7)${RESET}  Create namespace"
    echo "  ${CYAN}8)${RESET}  Set default namespace"
    print_menu_separator
    echo "  ${BOLD}${YELLOW}Resources${RESET}"
    echo "  ${CYAN}9)${RESET}  Get pods"
    echo "  ${CYAN}10)${RESET} Get services"
    echo "  ${CYAN}11)${RESET} Get deployments"
    echo "  ${CYAN}12)${RESET} Describe resource"
    echo "  ${CYAN}13)${RESET} Show pod logs"
    echo "  ${CYAN}14)${RESET} Apply manifest (YAML)"
    echo "  ${CYAN}15)${RESET} Delete resource"
    print_menu_separator
    echo "  ${CYAN}e)${RESET}  Show environment info"
    echo "  ${CYAN}0)${RESET}  Exit"
    echo
    read -r -p "Choose: " c
    echo
    case "${c:-}" in
      1)  install_kubectl || true; pause ;;
      2)  list_contexts || true; pause ;;
      3)  switch_context || true; pause ;;
      4)  show_current_context || true; pause ;;
      5)  cluster_overview || true; pause ;;
      6)  list_namespaces || true; pause ;;
      7)  create_namespace || true; pause ;;
      8)  set_default_namespace || true; pause ;;
      9)  get_pods || true; pause ;;
      10) get_services || true; pause ;;
      11) get_deployments || true; pause ;;
      12) describe_resource || true; pause ;;
      13) show_logs || true; pause ;;
      14) apply_manifest || true; pause ;;
      15) delete_resource || true; pause ;;
      e|E) show_env_info; pause ;;
      0) log_info "Bye!"; exit 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

main "$@"
