#!/usr/bin/env bash
# scripts/kopia.sh — Kopia backup manager (multi-distro)
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
register_cleanup

SCRIPT_NAME="Kopia Backup Manager"
SCRIPT_DESC="Install Kopia, manage repositories, snapshots and restores"

handle_standard_args "$@"

CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/kopia-menu"
CONFIG_FILE="${CONFIG_DIR}/config.env"

REPO_TYPE="${REPO_TYPE:-}"
REPO_PATH="${REPO_PATH:-}"
# shellcheck disable=SC1090
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE" || true

save_config() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    log_info "[DRY-RUN] Would create config directory: $CONFIG_DIR"
    log_info "[DRY-RUN] Would write configuration: $CONFIG_FILE"
    return 0
  fi
  mkdir -p "$CONFIG_DIR"
  cat > "$CONFIG_FILE" <<EOF
REPO_TYPE="${REPO_TYPE:-}"
REPO_PATH="${REPO_PATH:-}"
EOF
  chmod 600 "$CONFIG_FILE"
  log_ok "Configuration saved: $CONFIG_FILE"
}

# ---------------------------------------------------------------------------
# STATUS
# ---------------------------------------------------------------------------
show_kopia_status() {
  echo
  if is_installed kopia; then
    log_ok "Kopia: $(kopia --version 2>/dev/null)"
    if kopia repository status >/dev/null 2>&1; then
      log_ok "Repository: connected (type: ${REPO_TYPE:-unknown})"
      [[ -n "$REPO_PATH" ]] && log_info "  Path: $REPO_PATH"
    else
      log_warn "Repository: NOT connected"
    fi
  else
    log_warn "Kopia: NOT installed"
  fi
  echo
}

# ---------------------------------------------------------------------------
# INSTALL
# ---------------------------------------------------------------------------
install_kopia() {
  if is_installed kopia; then
    log_ok "Kopia already installed: $(kopia --version 2>/dev/null)"
    if ! ask_confirm "Reinstall Kopia?"; then return 0; fi
  fi

  require_internet
  check_sudo
  detect_package_manager

  case "$PKG_MANAGER" in
    apt)
      _install_kopia_apt
      ;;
    dnf|yum)
      _install_kopia_rpm
      ;;
    pacman)
      if is_installed yay; then
        run_cmd yay -S --noconfirm kopia-bin
      else
        log_warn "Install kopia-bin from AUR manually, or use binary install."
        _install_kopia_binary
      fi
      ;;
    *)
      _install_kopia_binary
      ;;
  esac

  log_ok "Kopia installed: $(kopia --version 2>/dev/null)"
}

_install_kopia_apt() {
  log_step "Installing Kopia via apt repository..."
  run_cmd_sudo apt-get update -y
  run_cmd_sudo apt-get install -y curl gpg apt-transport-https ca-certificates
  run_cmd_sudo install -d -m 0755 /etc/apt/keyrings
  local tmpdir; tmpdir="$(make_tmpdir)"
  download_file "https://kopia.io/signing-key" "${tmpdir}/kopia.key"
  run_cmd_sudo gpg --dearmor -o /etc/apt/keyrings/kopia.gpg < "${tmpdir}/kopia.key"
  echo "deb [signed-by=/etc/apt/keyrings/kopia.gpg] http://packages.kopia.io/apt/ stable main" \
    | sudo tee /etc/apt/sources.list.d/kopia.list > /dev/null
  run_cmd_sudo apt-get update -y
  run_cmd_sudo apt-get install -y kopia
}

_install_kopia_rpm() {
  log_step "Installing Kopia via RPM repository..."
  cat > /tmp/kopia.repo <<'EOF'
[kopia]
name=Kopia
baseurl=http://packages.kopia.io/rpm/stable/$basearch/
gpgcheck=1
gpgkey=https://kopia.io/signing-key
enabled=1
EOF
  run_cmd_sudo mv /tmp/kopia.repo /etc/yum.repos.d/kopia.repo
  # shellcheck disable=SC2086
  run_cmd sudo $PKG_INSTALL kopia
}

_install_kopia_binary() {
  log_step "Installing Kopia via binary download..."
  local arch
  arch="$(get_arch_suffix)"
  local tmpdir; tmpdir="$(make_tmpdir)"
  # Get latest version
  local version
  version="$(curl -fsSL https://api.github.com/repos/kopia/kopia/releases/latest \
    | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/' 2>/dev/null || echo "0.17.0")"
  local url="https://github.com/kopia/kopia/releases/download/v${version}/kopia-${version}-linux-${arch}.tar.gz"
  download_file "$url" "${tmpdir}/kopia.tar.gz"
  run_cmd tar -xzf "${tmpdir}/kopia.tar.gz" -C "${tmpdir}"
  run_cmd_sudo install -m 755 "${tmpdir}/kopia" /usr/local/bin/kopia
}

# ---------------------------------------------------------------------------
# REPOSITORY MANAGEMENT
# ---------------------------------------------------------------------------
repo_create_filesystem() {
  require_command kopia
  local path
  path="$(ask_input "Repository path (e.g., /mnt/backup/kopia-repo)")"
  require_not_empty "$path" "Repository path"
  run_cmd mkdir -p "$path"
  log_step "Creating Kopia repository at: $path"
  kopia repository create filesystem --path "$path"
  REPO_TYPE="filesystem"
  REPO_PATH="$path"
  save_config
  log_ok "Repository created and connected."
}

repo_connect_filesystem() {
  require_command kopia
  local path
  path="$(ask_input "Existing repository path")"
  require_not_empty "$path" "Repository path"
  [[ ! -d "$path" ]] && { log_error "Directory not found: $path"; return 1; }
  log_step "Connecting to Kopia repository: $path"
  kopia repository connect filesystem --path "$path"
  REPO_TYPE="filesystem"
  REPO_PATH="$path"
  save_config
  log_ok "Repository connected."
}

repo_create_s3() {
  require_command kopia
  local bucket endpoint access secret
  bucket="$(ask_input "S3 bucket name")"
  endpoint="$(ask_input "S3 endpoint (leave empty for AWS)" "")"
  access="$(ask_input "Access key ID")"
  secret="$(ask_secret "Secret access key (input hidden)")"

  local args=("repository" "create" "s3" "--bucket=$bucket" "--access-key-id=$access" "--secret-access-key=$secret")
  [[ -n "$endpoint" ]] && args+=("--endpoint=$endpoint")

  log_step "Creating S3 repository..."
  kopia "${args[@]}"
  REPO_TYPE="s3"
  REPO_PATH="s3://$bucket"
  save_config
  log_ok "S3 repository created."
}

repo_disconnect() {
  require_command kopia
  if kopia repository status >/dev/null 2>&1; then
    kopia repository disconnect
    log_ok "Repository disconnected."
  else
    log_warn "No repository connected."
  fi
}

show_repo_info() {
  require_command kopia
  if kopia repository status >/dev/null 2>&1; then
    kopia repository status
    echo
    log_info "Config: REPO_TYPE=${REPO_TYPE:-}, REPO_PATH=${REPO_PATH:-}"
  else
    log_warn "No repository connected."
  fi
}

# ---------------------------------------------------------------------------
# SNAPSHOTS
# ---------------------------------------------------------------------------
snapshot_create() {
  require_command kopia
  if ! kopia repository status >/dev/null 2>&1; then
    log_error "No repository connected. Connect one first."
    return 1
  fi
  local src
  src="$(ask_input "Directory to backup (e.g., /home/$USER/Documents)")"
  require_not_empty "$src" "Source directory"
  [[ ! -e "$src" ]] && { log_error "Path not found: $src"; return 1; }

  local desc
  desc="$(ask_input "Description (optional)" "")"

  log_step "Creating snapshot of: $src"
  if [[ -n "$desc" ]]; then
    kopia snapshot create "$src" --description "$desc"
  else
    kopia snapshot create "$src"
  fi
  log_ok "Snapshot created."
}

snapshot_list() {
  require_command kopia
  if ! kopia repository status >/dev/null 2>&1; then
    log_error "No repository connected."
    return 1
  fi
  log_info "Snapshots:"
  kopia snapshot list
}

snapshot_restore() {
  require_command kopia
  if ! kopia repository status >/dev/null 2>&1; then
    log_error "No repository connected."
    return 1
  fi
  snapshot_list || true
  echo
  local sid
  sid="$(ask_input "Snapshot ID to restore")"
  require_not_empty "$sid" "Snapshot ID"
  local target
  target="$(ask_input "Restore destination" "/tmp/kopia-restore")"
  run_cmd mkdir -p "$target"
  log_step "Restoring snapshot $sid to $target..."
  kopia snapshot restore "$sid" --target-path "$target"
  log_ok "Restore complete: $target"
}

snapshot_delete() {
  require_command kopia
  snapshot_list || true
  echo
  local sid
  sid="$(ask_input "Snapshot ID to delete")"
  require_not_empty "$sid" "Snapshot ID"
  if ask_confirm "Delete snapshot $sid?"; then
    kopia snapshot delete "$sid" --delete
    log_ok "Snapshot deleted."
  fi
}

# ---------------------------------------------------------------------------
# MAINTENANCE
# ---------------------------------------------------------------------------
run_maintenance() {
  require_command kopia
  if ! kopia repository status >/dev/null 2>&1; then
    log_error "No repository connected."
    return 1
  fi
  log_step "Running maintenance (may take a while)..."
  kopia maintenance run || kopia maintenance run --full || true
  log_ok "Maintenance complete."
}

# ---------------------------------------------------------------------------
# MENU
# ---------------------------------------------------------------------------
main() {
  while true; do
    print_script_header "$SCRIPT_NAME" "$SCRIPT_DESC"
    show_kopia_status
    echo "  ${BOLD}${YELLOW}Installation${RESET}"
    echo "  ${CYAN}1)${RESET} Install Kopia"
    print_menu_separator
    echo "  ${BOLD}${YELLOW}Repository${RESET}"
    echo "  ${CYAN}2)${RESET} Create local (filesystem) repository"
    echo "  ${CYAN}3)${RESET} Connect existing local repository"
    echo "  ${CYAN}4)${RESET} Create S3 repository"
    echo "  ${CYAN}5)${RESET} Disconnect repository"
    echo "  ${CYAN}6)${RESET} Show repository info"
    print_menu_separator
    echo "  ${BOLD}${YELLOW}Snapshots${RESET}"
    echo "  ${CYAN}7)${RESET} Create snapshot (backup)"
    echo "  ${CYAN}8)${RESET} List snapshots"
    echo "  ${CYAN}9)${RESET} Restore snapshot"
    echo "  ${CYAN}10)${RESET} Delete snapshot"
    print_menu_separator
    echo "  ${CYAN}11)${RESET} Run maintenance"
    echo "  ${CYAN}e)${RESET}  Show environment info"
    echo "  ${CYAN}0)${RESET}  Exit"
    echo
    read -r -p "Choose: " c
    echo
    case "${c:-}" in
      1)  install_kopia || true; pause ;;
      2)  repo_create_filesystem || true; pause ;;
      3)  repo_connect_filesystem || true; pause ;;
      4)  repo_create_s3 || true; pause ;;
      5)  repo_disconnect || true; pause ;;
      6)  show_repo_info || true; pause ;;
      7)  snapshot_create || true; pause ;;
      8)  snapshot_list || true; pause ;;
      9)  snapshot_restore || true; pause ;;
      10) snapshot_delete || true; pause ;;
      11) run_maintenance || true; pause ;;
      e|E) show_env_info; pause ;;
      0) log_info "Bye!"; exit 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

main "$@"
