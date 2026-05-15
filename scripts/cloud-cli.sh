#!/usr/bin/env bash
# scripts/cloud-cli.sh — Cloud CLI installer and configurator (AWS / Azure / GCP)
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
register_cleanup

SCRIPT_NAME="Cloud CLI Manager"
SCRIPT_DESC="Install and configure AWS / Azure / GCP CLI tools"

handle_standard_args "$@"

# ---------------------------------------------------------------------------
# STATUS
# ---------------------------------------------------------------------------
show_cloud_status() {
  echo
  log_info "=== Cloud CLI Status ==="
  if is_installed aws; then
    log_ok "AWS CLI: $(aws --version 2>&1 | head -1)"
  else
    log_warn "AWS CLI: NOT installed"
  fi
  if is_installed az; then
    log_ok "Azure CLI: $(az --version 2>&1 | head -1)"
  else
    log_warn "Azure CLI: NOT installed"
  fi
  if is_installed gcloud; then
    log_ok "GCloud SDK: $(gcloud --version 2>&1 | head -1)"
  else
    log_warn "GCloud SDK: NOT installed"
  fi
  echo
}

# ---------------------------------------------------------------------------
# AWS CLI
# ---------------------------------------------------------------------------
install_aws_cli() {
  if is_installed aws; then
    log_ok "AWS CLI already installed: $(aws --version 2>&1)"
    if ! ask_confirm "Reinstall / update?"; then return 0; fi
  fi

  require_internet
  check_sudo
  detect_package_manager

  local arch
  arch="$(get_arch_suffix)"
  local tmpdir
  tmpdir="$(make_tmpdir)"

  log_step "Downloading AWS CLI v2 for ${arch}..."
  local url="https://awscli.amazonaws.com/awscli-exe-linux-${arch}.zip"
  download_file "$url" "${tmpdir}/awscliv2.zip"

  require_command unzip "unzip (install via package manager)"
  log_step "Extracting..."
  run_cmd unzip -q "${tmpdir}/awscliv2.zip" -d "${tmpdir}"

  log_step "Installing AWS CLI..."
  if is_installed aws; then
    run_cmd_sudo "${tmpdir}/aws/install" --update
  else
    run_cmd_sudo "${tmpdir}/aws/install"
  fi

  log_ok "AWS CLI installed: $(aws --version 2>&1)"
  log_info "Run 'aws configure' to set your credentials."
}

configure_aws() {
  require_command aws "Install AWS CLI first (option 1)"
  echo
  log_info "=== AWS Configuration ==="
  echo "  This will run 'aws configure' interactively."
  echo "  You will need: Access Key ID, Secret Access Key, Region, Output format."
  echo
  if ask_confirm "Proceed with 'aws configure'?"; then
    aws configure
    log_ok "AWS configured. Test with: aws sts get-caller-identity"
  fi
}

check_aws_login() {
  require_command aws
  log_step "Checking AWS login..."
  if aws sts get-caller-identity 2>/dev/null; then
    log_ok "AWS login OK."
  else
    log_warn "AWS not logged in or credentials invalid."
    log_info "Run: aws configure"
  fi
}

# ---------------------------------------------------------------------------
# AZURE CLI
# ---------------------------------------------------------------------------
install_azure_cli() {
  if is_installed az; then
    log_ok "Azure CLI already installed: $(az --version 2>&1 | head -1)"
    if ! ask_confirm "Reinstall / update?"; then return 0; fi
  fi

  require_internet
  check_sudo
  detect_package_manager

  case "$PKG_MANAGER" in
    apt)
      log_step "Installing Azure CLI via Microsoft repository..."
      run_cmd_sudo apt-get update -y
      run_cmd_sudo apt-get install -y ca-certificates curl apt-transport-https lsb-release gnupg
      local tmpdir; tmpdir="$(make_tmpdir)"
      download_file "https://packages.microsoft.com/keys/microsoft.asc" "${tmpdir}/microsoft.asc"
      run_cmd_sudo install -o root -g root -m 644 "${tmpdir}/microsoft.asc" /etc/apt/trusted.gpg.d/microsoft.asc
      local codename
      codename="$(lsb_release -cs 2>/dev/null || echo "focal")"
      echo "deb [arch=$(dpkg --print-architecture)] https://packages.microsoft.com/repos/azure-cli/ ${codename} main" \
        | sudo tee /etc/apt/sources.list.d/azure-cli.list
      run_cmd_sudo apt-get update -y
      run_cmd_sudo apt-get install -y azure-cli
      ;;
    dnf|yum)
      log_step "Installing Azure CLI via rpm..."
      run_cmd_sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
      cat > /tmp/azure-cli.repo <<'EOF'
[azure-cli]
name=Azure CLI
baseurl=https://packages.microsoft.com/yumrepos/azure-cli
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
      run_cmd_sudo mv /tmp/azure-cli.repo /etc/yum.repos.d/azure-cli.repo
      # shellcheck disable=SC2086
      run_cmd sudo $PKG_INSTALL azure-cli
      ;;
    pacman)
      log_step "Installing azure-cli via AUR (using yay/paru)..."
      if is_installed yay; then
        run_cmd yay -S --noconfirm azure-cli
      elif is_installed paru; then
        run_cmd paru -S --noconfirm azure-cli
      else
        log_warn "AUR helper not found. Install yay or paru first, then 'yay -S azure-cli'."
        return 1
      fi
      ;;
    *)
      log_step "Trying pip install..."
      if is_installed pip3; then
        run_cmd pip3 install azure-cli
      else
        log_error "Cannot install Azure CLI automatically on this system."
        log_info "Visit: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli"
        return 1
      fi
      ;;
  esac

  log_ok "Azure CLI installed: $(az --version 2>&1 | head -1)"
  log_info "Run 'az login' to authenticate."
}

configure_azure() {
  require_command az "Install Azure CLI first (option 4)"
  log_step "Running 'az login'..."
  az login
  log_ok "Azure login complete. Test with: az account show"
}

check_azure_login() {
  require_command az
  log_step "Checking Azure login..."
  if az account show 2>/dev/null; then
    log_ok "Azure login OK."
  else
    log_warn "Not logged in to Azure. Run: az login"
  fi
}

# ---------------------------------------------------------------------------
# GCP
# ---------------------------------------------------------------------------
install_gcloud() {
  if is_installed gcloud; then
    log_ok "Google Cloud SDK already installed: $(gcloud --version 2>&1 | head -1)"
    if ! ask_confirm "Reinstall / update?"; then return 0; fi
  fi

  require_internet
  check_sudo
  detect_package_manager

  case "$PKG_MANAGER" in
    apt)
      log_step "Installing Google Cloud SDK via apt..."
      run_cmd_sudo apt-get update -y
      run_cmd_sudo apt-get install -y ca-certificates curl apt-transport-https gnupg
      local tmpdir; tmpdir="$(make_tmpdir)"
      download_file "https://packages.cloud.google.com/apt/doc/apt-key.gpg" "${tmpdir}/cloud.google.gpg"
      run_cmd_sudo mkdir -p /usr/share/keyrings
      run_cmd_sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg < "${tmpdir}/cloud.google.gpg"
      echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
        | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list
      run_cmd_sudo apt-get update -y
      run_cmd_sudo apt-get install -y google-cloud-cli
      ;;
    dnf|yum)
      log_step "Installing Google Cloud SDK via rpm..."
      cat > /tmp/google-cloud-sdk.repo <<'EOF'
[google-cloud-cli]
name=Google Cloud CLI
baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el8-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
      run_cmd_sudo mv /tmp/google-cloud-sdk.repo /etc/yum.repos.d/
      # shellcheck disable=SC2086
      run_cmd sudo $PKG_INSTALL google-cloud-cli
      ;;
    *)
      log_step "Installing via snap..."
      if is_installed snap; then
        run_cmd_sudo snap install google-cloud-cli --classic
      else
        log_error "Unsupported package manager for automatic GCloud install."
        log_info "Visit: https://cloud.google.com/sdk/docs/install"
        return 1
      fi
      ;;
  esac

  log_ok "Google Cloud SDK installed."
  log_info "Run 'gcloud init' to configure."
}

configure_gcloud() {
  require_command gcloud "Install GCloud SDK first (option 7)"
  log_step "Running 'gcloud init'..."
  gcloud init
  log_ok "GCloud configured."
}

check_gcloud_login() {
  require_command gcloud
  log_step "Checking GCloud login..."
  if gcloud auth list --format="value(account)" 2>/dev/null | grep -q '@'; then
    log_ok "GCloud login OK."
    gcloud auth list
  else
    log_warn "Not logged in to GCloud. Run: gcloud auth login"
  fi
}

# ---------------------------------------------------------------------------
# MENU
# ---------------------------------------------------------------------------
main() {
  while true; do
    print_script_header "$SCRIPT_NAME" "$SCRIPT_DESC"
    show_cloud_status
    echo "  ${BOLD}${YELLOW}AWS CLI${RESET}"
    echo "  ${CYAN}1)${RESET} Install AWS CLI v2"
    echo "  ${CYAN}2)${RESET} Configure AWS (aws configure)"
    echo "  ${CYAN}3)${RESET} Check AWS login"
    print_menu_separator
    echo "  ${BOLD}${YELLOW}Azure CLI${RESET}"
    echo "  ${CYAN}4)${RESET} Install Azure CLI"
    echo "  ${CYAN}5)${RESET} Login to Azure (az login)"
    echo "  ${CYAN}6)${RESET} Check Azure login"
    print_menu_separator
    echo "  ${BOLD}${YELLOW}Google Cloud${RESET}"
    echo "  ${CYAN}7)${RESET} Install Google Cloud SDK"
    echo "  ${CYAN}8)${RESET} Configure GCloud (gcloud init)"
    echo "  ${CYAN}9)${RESET} Check GCloud login"
    print_menu_separator
    echo "  ${CYAN}e)${RESET} Show environment info"
    echo "  ${CYAN}0)${RESET} Exit"
    echo
    read -r -p "Choose: " c
    echo
    case "${c:-}" in
      1) install_aws_cli || true; pause ;;
      2) configure_aws || true; pause ;;
      3) check_aws_login || true; pause ;;
      4) install_azure_cli || true; pause ;;
      5) configure_azure || true; pause ;;
      6) check_azure_login || true; pause ;;
      7) install_gcloud || true; pause ;;
      8) configure_gcloud || true; pause ;;
      9) check_gcloud_login || true; pause ;;
      e|E) show_env_info; pause ;;
      0) log_info "Bye!"; exit 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

main "$@"
