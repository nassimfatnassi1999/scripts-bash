#!/usr/bin/env bash
# scripts/setup-dev-linux.sh — Generic Linux developer environment setup
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
register_cleanup

SCRIPT_NAME="Linux Dev Environment Setup"
SCRIPT_DESC="Set up a complete developer workstation on any Linux distribution"

handle_standard_args "$@"

# ---------------------------------------------------------------------------
# COMPONENTS
# ---------------------------------------------------------------------------
install_base_tools() {
  log_step "Installing base tools..."
  check_sudo || return 1
  detect_package_manager || return 1
  update_package_index || return 1

  local base_pkgs=()
  case "$PKG_MANAGER" in
    apt)
      base_pkgs=(curl wget git build-essential software-properties-common
                 ca-certificates gnupg lsb-release unzip tar jq vim nano make)
      ;;
    dnf|yum)
      base_pkgs=(curl wget git gcc gcc-c++ make ca-certificates gnupg2
                 unzip tar jq vim nano)
      ;;
    pacman)
      base_pkgs=(curl wget git base-devel ca-certificates gnupg unzip tar jq vim nano make)
      ;;
    zypper)
      base_pkgs=(curl wget git gcc gcc-c++ make ca-certificates gpg2 unzip tar jq vim nano)
      ;;
    apk)
      base_pkgs=(curl wget git build-base ca-certificates gnupg unzip tar jq vim nano make)
      ;;
    *)
      log_warn "Unknown package manager. Skipping base tool install."
      return 0
      ;;
  esac

  for pkg in "${base_pkgs[@]}"; do
    if ! is_installed "${pkg%%[- ]*}"; then
      install_package "$pkg" 2>/dev/null || log_warn "Failed to install: $pkg"
    else
      log_ok "Already installed: $pkg"
    fi
  done
}

install_vscode() {
  if is_installed code; then
    log_ok "VS Code already installed: $(code --version | head -1)"
    return 0
  fi
  require_internet
  check_sudo || return 1
  detect_package_manager || return 1
  log_step "Installing Visual Studio Code..."
  case "$PKG_MANAGER" in
    apt)
      local tmpdir; tmpdir="$(make_tmpdir)"
      download_file "https://packages.microsoft.com/keys/microsoft.asc" "${tmpdir}/microsoft.asc" || return 1
      run_cmd_sudo gpg --batch --yes --dearmor -o /usr/share/keyrings/packages.microsoft.gpg < "${tmpdir}/microsoft.asc" || return 1
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
        | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null || return 1
      run_cmd_sudo apt-get update -y || return 1
      run_cmd_sudo apt-get install -y code || return 1
      ;;
    dnf|yum)
      local tmpdir; tmpdir="$(make_tmpdir)"
      download_file "https://packages.microsoft.com/keys/microsoft.asc" "${tmpdir}/microsoft.asc" || return 1
      run_cmd_sudo rpm --import "${tmpdir}/microsoft.asc" || return 1
      cat > "${tmpdir}/vscode.repo" <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
      run_cmd_sudo mv "${tmpdir}/vscode.repo" /etc/yum.repos.d/vscode.repo || return 1
      install_package code || return 1
      ;;
    pacman)
      if is_installed yay; then
        run_cmd yay -S --noconfirm visual-studio-code-bin
      else
        log_warn "Install VS Code manually from: https://code.visualstudio.com"
        return 0
      fi
      ;;
    *)
      if is_installed snap; then
        run_cmd_sudo snap install code --classic
      else
        log_warn "Cannot install VS Code automatically. Visit: https://code.visualstudio.com"
        return 0
      fi
      ;;
  esac
  log_ok "VS Code installed."
}

install_nvm_node() {
  log_step "Installing NVM + Node.js LTS..."
  require_internet
  local nvm_version
  nvm_version="$(curl -fsSL https://api.github.com/repos/nvm-sh/nvm/releases/latest \
    | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/' 2>/dev/null || echo "0.39.7")"

  if [[ -d "${HOME}/.nvm" ]]; then
    log_ok "NVM already installed."
  else
    log_step "Installing NVM v${nvm_version}..."
    local tmpdir; tmpdir="$(make_tmpdir)"
    download_file "https://raw.githubusercontent.com/nvm-sh/nvm/v${nvm_version}/install.sh" "${tmpdir}/nvm-install.sh" || return 1
    bash "${tmpdir}/nvm-install.sh" || return 1
    log_ok "NVM installed."
  fi

  # Source NVM
  export NVM_DIR="${HOME}/.nvm"
  # shellcheck disable=SC1091
  [[ -s "${NVM_DIR}/nvm.sh" ]] && source "${NVM_DIR}/nvm.sh"

  if ! is_installed nvm 2>/dev/null && ! command -v nvm >/dev/null 2>&1; then
    log_warn "nvm not found in PATH after install. Restart shell or source ~/.bashrc"
    return 0
  fi

  log_step "Installing Node.js LTS..."
  nvm install --lts || return 1
  nvm use --lts || return 1
  nvm alias default 'lts/*' || return 1
  log_ok "Node.js: $(node -v) | npm: $(npm -v)"
}

install_docker_devsetup() {
  if is_installed docker; then
    log_ok "Docker already installed."
    return 0
  fi
  if ask_confirm "Install Docker?"; then
    bash "${SCRIPT_DIR}/docker.sh" || true
  fi
}

install_git_config() {
  log_step "Configuring Git..."
  local name email
  name="$(ask_input "Git user.name" "$(git config --global user.name 2>/dev/null || echo '')")"
  email="$(ask_input "Git user.email" "$(git config --global user.email 2>/dev/null || echo '')")"
  [[ -n "$name" ]]  && git config --global user.name "$name"
  [[ -n "$email" ]] && git config --global user.email "$email"
  git config --global core.editor "${EDITOR:-nano}"
  git config --global init.defaultBranch main
  git config --global pull.rebase false
  git config --global color.ui auto
  log_ok "Git configured: $name <$email>"
}

install_python_tools() {
  log_step "Installing Python tools..."
  check_sudo || return 1
  detect_package_manager || return 1
  case "$PKG_MANAGER" in
    apt)     run_cmd_sudo apt-get install -y python3 python3-pip python3-venv ;;
    dnf|yum) install_packages python3 python3-pip ;;
    pacman)  run_cmd_sudo pacman -S --noconfirm python python-pip ;;
    zypper)  run_cmd_sudo zypper install -y python3 python3-pip ;;
    apk)     run_cmd_sudo apk add python3 py3-pip ;;
    *) log_warn "Unknown package manager for Python install." ;;
  esac
  log_ok "Python installed: $(python3 --version 2>/dev/null || true)"
}

install_zsh_oh_my_zsh() {
  if is_installed zsh; then
    log_ok "Zsh already installed."
  else
    log_step "Installing Zsh..."
    check_sudo || return 1
    install_package zsh || return 1
  fi

  if [[ ! -d "${HOME}/.oh-my-zsh" ]]; then
    if ask_confirm "Install Oh My Zsh?"; then
      require_internet
      local tmpdir; tmpdir="$(make_tmpdir)"
      download_file "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh" \
        "${tmpdir}/omz-install.sh" || return 1
      RUNZSH=no CHSH=no bash "${tmpdir}/omz-install.sh" || return 1
      log_ok "Oh My Zsh installed."
    fi
  else
    log_ok "Oh My Zsh already installed."
  fi

  if ask_confirm "Set Zsh as default shell?"; then
    check_sudo || return 1
    run_cmd_sudo chsh -s "$(which zsh)" "$(whoami)" || return 1
    log_ok "Default shell changed to Zsh. Log out and back in."
  fi
}

install_vscode_extensions() {
  if ! is_installed code; then
    log_warn "VS Code not installed. Install it first."
    return 0
  fi
  log_step "Installing VS Code extensions..."
  local extensions=(
    "ms-python.python"
    "ms-azuretools.vscode-docker"
    "ms-kubernetes-tools.vscode-kubernetes-tools"
    "hashicorp.terraform"
    "redhat.ansible"
    "timonwong.shellcheck"
    "esbenp.prettier-vscode"
    "dbaeumer.vscode-eslint"
    "eamodio.gitlens"
    "ms-vscode.makefile-tools"
  )
  for ext in "${extensions[@]}"; do
    code --install-extension "$ext" --force 2>/dev/null && log_ok "Installed: $ext" || log_warn "Failed: $ext"
  done
}

run_full_setup() {
  log_step "=== Full Linux Dev Environment Setup ==="
  echo
  log_info "The following components will be installed:"
  echo "  - Base tools (curl, wget, git, build-essential, jq, etc.)"
  echo "  - VS Code"
  echo "  - NVM + Node.js LTS"
  echo "  - Python 3 + pip"
  echo "  - Git configuration"
  echo "  - Zsh + Oh My Zsh (optional)"
  echo "  - Docker (optional)"
  echo "  - VS Code extensions"
  echo
  if ! ask_confirm "Proceed with full setup?"; then
    log_warn "Cancelled."
    return 0
  fi

  install_base_tools
  install_vscode
  install_nvm_node
  install_python_tools
  install_git_config
  install_zsh_oh_my_zsh
  install_docker_devsetup
  install_vscode_extensions

  echo
  log_ok "=== Dev environment setup complete! ==="
  log_info "You may need to restart your terminal or log out/in."
}

# ---------------------------------------------------------------------------
# MENU
# ---------------------------------------------------------------------------
main() {
  while true; do
    print_script_header "$SCRIPT_NAME" "$SCRIPT_DESC"
    echo "  ${CYAN}1)${RESET}  Full setup (all components)"
    print_menu_separator
    echo "  ${CYAN}2)${RESET}  Install base tools (curl, git, jq, make, etc.)"
    echo "  ${CYAN}3)${RESET}  Install VS Code"
    echo "  ${CYAN}4)${RESET}  Install NVM + Node.js LTS"
    echo "  ${CYAN}5)${RESET}  Install Python 3 + pip"
    echo "  ${CYAN}6)${RESET}  Configure Git"
    echo "  ${CYAN}7)${RESET}  Install Zsh + Oh My Zsh"
    echo "  ${CYAN}8)${RESET}  Install Docker"
    echo "  ${CYAN}9)${RESET}  Install VS Code extensions"
    echo "  ${CYAN}e)${RESET}  Show environment info"
    print_menu_separator
    echo "  ${CYAN}0)${RESET}  Exit"
    echo
    read -r -p "Choose: " c
    echo
    case "${c:-}" in
      1) run_full_setup || true; pause ;;
      2) install_base_tools || true; pause ;;
      3) install_vscode || true; pause ;;
      4) install_nvm_node || true; pause ;;
      5) install_python_tools || true; pause ;;
      6) install_git_config || true; pause ;;
      7) install_zsh_oh_my_zsh || true; pause ;;
      8) install_docker_devsetup || true; pause ;;
      9) install_vscode_extensions || true; pause ;;
      e|E) show_env_info; pause ;;
      0) log_info "Bye!"; exit 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

main "$@"
