#!/usr/bin/env bash
# scripts/docker.sh — Docker & Docker Compose installer and manager
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
register_cleanup

SCRIPT_NAME="Docker Manager"
SCRIPT_DESC="Install Docker Engine, Docker Compose, configure groups and test"

handle_standard_args "$@"

# ---------------------------------------------------------------------------
# STATUS
# ---------------------------------------------------------------------------
show_docker_status() {
  echo
  log_info "=== Docker Status ==="
  if is_installed docker; then
    log_ok "Docker: $(docker --version)"
    if systemd_available && systemctl is-active --quiet docker 2>/dev/null; then
      if docker info >/dev/null 2>&1; then
        log_ok "Docker daemon: running and accessible"
      else
        log_warn "Docker daemon: running, but current user cannot access /var/run/docker.sock"
        log_info "Fix: option 2 adds your user to the docker group; then log out/in or run: newgrp docker"
      fi
    elif docker info >/dev/null 2>&1; then
      log_ok "Docker daemon: running and accessible"
    else
      log_warn "Docker daemon: NOT running (start with: sudo systemctl start docker)"
    fi
  else
    log_warn "Docker: NOT installed"
  fi

  if docker compose version >/dev/null 2>&1; then
    log_ok "Docker Compose (plugin): $(docker compose version)"
  elif is_installed docker-compose; then
    log_ok "Docker Compose (standalone): $(docker-compose --version)"
  else
    log_warn "Docker Compose: NOT installed"
  fi
  echo
}

# ---------------------------------------------------------------------------
# INSTALL DOCKER
# ---------------------------------------------------------------------------
install_docker() {
  if is_installed docker; then
    log_ok "Docker already installed: $(docker --version)"
    if ! ask_confirm "Reinstall Docker?"; then return 0; fi
  fi

  require_internet
  check_sudo || return 1
  detect_package_manager || return 1

  case "$PKG_MANAGER" in
    apt)
      _install_docker_apt || return 1
      ;;
    dnf|yum)
      _install_docker_rpm || return 1
      ;;
    pacman)
      _install_docker_arch || return 1
      ;;
    zypper)
      _install_docker_zypper || return 1
      ;;
    apk)
      _install_docker_alpine || return 1
      ;;
    *)
      log_warn "Unsupported package manager. Trying convenience script..."
      _install_docker_script || return 1
      ;;
  esac

  # Enable and start Docker
  if systemd_available; then
    run_cmd_sudo systemctl enable --now docker || return 1
    log_ok "Docker service enabled and started."
  fi

  require_command docker || return 1
  log_ok "Docker installed: $(docker --version)"
}

_install_docker_apt() {
  log_step "Installing Docker on Debian/Ubuntu-based system..."
  run_cmd_sudo apt-get update -y || return 1
  run_cmd_sudo apt-get install -y ca-certificates curl gnupg lsb-release || return 1

  local arch codename
  arch="$(dpkg --print-architecture)"

  # Detect Ubuntu vs Debian codename for the Docker repo
  if [[ "$OS_ID" == "ubuntu" || "$OS_ID_LIKE" == *ubuntu* ]]; then
    codename="$(lsb_release -cs 2>/dev/null || echo "jammy")"
  elif [[ "$OS_ID" == "debian" || "$OS_ID_LIKE" == *debian* ]]; then
    codename="$(lsb_release -cs 2>/dev/null || echo "bullseye")"
  else
    # Pop!_OS and others that are Ubuntu-based
    codename="$(lsb_release -cs 2>/dev/null || echo "jammy")"
  fi

  log_step "Adding Docker GPG key and repository..."
  run_cmd_sudo mkdir -p /etc/apt/keyrings || return 1
  local tmpdir; tmpdir="$(make_tmpdir)"
  download_file "https://download.docker.com/linux/ubuntu/gpg" "${tmpdir}/docker.gpg" || return 1
  run_cmd_sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg < "${tmpdir}/docker.gpg" || return 1
  run_cmd_sudo chmod a+r /etc/apt/keyrings/docker.gpg || return 1

  echo "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${codename} stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null || return 1

  run_cmd_sudo apt-get update -y || return 1
  run_cmd_sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || return 1
}

_install_docker_rpm() {
  log_step "Installing Docker on Fedora/RHEL/CentOS..."

  local repo_url
  if [[ "$PKG_MANAGER" == "dnf" ]]; then
    run_cmd_sudo dnf remove -y docker docker-client docker-client-latest docker-common \
      docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true

    if [[ "$OS_ID" == "fedora" ]]; then
      repo_url="https://download.docker.com/linux/fedora/docker-ce.repo"
    else
      repo_url="https://download.docker.com/linux/centos/docker-ce.repo"
    fi

    _dnf_add_repo "$repo_url" || return 1
    run_cmd_sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || return 1
  else
    run_cmd_sudo yum remove -y docker docker-client docker-client-latest docker-common \
      docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true
    run_cmd_sudo yum install -y yum-utils || return 1
    run_cmd_sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo || return 1
    run_cmd_sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || return 1
  fi
}

_dnf_add_repo() {
  local repo_url="$1"

  if ! dnf config-manager --help >/dev/null 2>&1; then
    run_cmd_sudo dnf install -y dnf-plugins-core || return 1
  fi

  if dnf config-manager --help 2>/dev/null | grep -q 'addrepo'; then
    run_cmd_sudo dnf config-manager addrepo --from-repofile="$repo_url" || return 1
  else
    run_cmd_sudo dnf config-manager --add-repo "$repo_url" || return 1
  fi
}

_install_docker_arch() {
  log_step "Installing Docker on Arch/Manjaro..."
  run_cmd_sudo pacman -S --noconfirm docker docker-compose || return 1
}

_install_docker_zypper() {
  log_step "Installing Docker on openSUSE..."
  run_cmd_sudo zypper install -y docker docker-compose || return 1
}

_install_docker_alpine() {
  log_step "Installing Docker on Alpine..."
  run_cmd_sudo apk add docker docker-compose || return 1
  run_cmd_sudo rc-update add docker boot || return 1
  run_cmd_sudo service docker start || return 1
}

_install_docker_script() {
  log_step "Using Docker convenience script..."
  local tmpdir; tmpdir="$(make_tmpdir)"
  download_file "https://get.docker.com" "${tmpdir}/get-docker.sh" || return 1
  run_cmd_sudo sh "${tmpdir}/get-docker.sh" || return 1
}

# ---------------------------------------------------------------------------
# ADD USER TO DOCKER GROUP
# ---------------------------------------------------------------------------
add_user_docker_group() {
  check_sudo || return 1
  local target_user
  target_user="$(ask_input "Username to add to docker group" "${SUDO_USER:-$(whoami)}")"

  if ! user_exists "$target_user"; then
    log_error "User not found: $target_user"
    return 1
  fi

  if groups "$target_user" | grep -q '\bdocker\b'; then
    log_ok "User '$target_user' is already in the docker group."
    return 0
  fi

  if ! group_exists "docker"; then
    log_step "Creating docker group..."
    run_cmd_sudo groupadd docker || return 1
  fi

  run_cmd_sudo usermod -aG docker "$target_user" || return 1
  log_ok "User '$target_user' added to docker group."
  log_warn "You must log out and log back in (or run 'newgrp docker') for this to take effect."
}

# ---------------------------------------------------------------------------
# TEST DOCKER
# ---------------------------------------------------------------------------
test_docker() {
  require_command docker
  if ! docker info >/dev/null 2>&1; then
    if systemd_available && ! systemctl is-active --quiet docker 2>/dev/null; then
      log_warn "Docker daemon is not running."
      if ask_confirm "Start Docker service now?"; then
        check_sudo || return 1
        run_cmd_sudo systemctl start docker || return 1
      else
        log_error "Docker test cannot run while the daemon is stopped."
        log_info "Start it with option 4, or run: sudo systemctl start docker"
        return 1
      fi
    fi
  fi

  log_step "Testing Docker with hello-world container..."
  if run_cmd docker run --rm hello-world; then
    log_ok "Docker is working correctly!"
  elif command -v sudo >/dev/null 2>&1 && ask_confirm "Retry test with sudo?"; then
    check_sudo || return 1
    run_cmd_sudo docker run --rm hello-world || return 1
    log_ok "Docker works with sudo."
    log_warn "For non-sudo Docker, use option 2 to add your user to the docker group, then log out/in or run 'newgrp docker'."
  else
    log_error "Docker test failed."
    log_info "Check: sudo systemctl status docker"
    log_info "If the daemon is running, add your user to the docker group with option 2."
  fi
}

# ---------------------------------------------------------------------------
# COMPOSE
# ---------------------------------------------------------------------------
create_example_compose() {
  local compose_file
  compose_file="$(ask_input "Output compose file path" "$(pwd)/docker-compose.yml")"
  if [[ -f "$compose_file" ]]; then
    if ! ask_confirm "File exists. Overwrite?"; then return 0; fi
    backup_file "$compose_file"
  fi
  cat > "$compose_file" <<'EOF'
version: '3.9'

services:
  app:
    image: nginx:latest
    container_name: my-nginx
    ports:
      - "8080:80"
    volumes:
      - ./html:/usr/share/nginx/html:ro
    networks:
      - mynet
    restart: unless-stopped

  # Example: add a database
  # db:
  #   image: postgres:15
  #   container_name: my-postgres
  #   environment:
  #     POSTGRES_USER: myuser
  #     POSTGRES_PASSWORD: ${DB_PASSWORD}
  #     POSTGRES_DB: mydb
  #   volumes:
  #     - pg_data:/var/lib/postgresql/data
  #   networks:
  #     - mynet
  #   restart: unless-stopped

networks:
  mynet:
    driver: bridge

# volumes:
#   pg_data:
EOF
  log_ok "Docker Compose file created: $compose_file"
}

# ---------------------------------------------------------------------------
# MANAGE DOCKER SERVICE
# ---------------------------------------------------------------------------
manage_docker_service() {
  if ! systemd_available; then
    log_warn "systemd not available. Cannot manage Docker service."
    return 0
  fi
  echo
  echo "  1) Start Docker"
  echo "  2) Stop Docker"
  echo "  3) Restart Docker"
  echo "  4) Enable Docker (autostart)"
  echo "  5) Disable Docker (no autostart)"
  echo "  6) Show Docker status"
  echo "  0) Back"
  echo
  read -r -p "Choose: " c
  case "${c:-}" in
    1) run_cmd_sudo systemctl start docker && log_ok "Docker started." ;;
    2) run_cmd_sudo systemctl stop docker && log_ok "Docker stopped." ;;
    3) run_cmd_sudo systemctl restart docker && log_ok "Docker restarted." ;;
    4) run_cmd_sudo systemctl enable docker && log_ok "Docker enabled on boot." ;;
    5) run_cmd_sudo systemctl disable docker && log_ok "Docker disabled on boot." ;;
    6) service_status docker ;;
    0) return 0 ;;
    *) log_warn "Invalid option." ;;
  esac
}

# ---------------------------------------------------------------------------
# MENU
# ---------------------------------------------------------------------------
main() {
  while true; do
    print_script_header "$SCRIPT_NAME" "$SCRIPT_DESC"
    show_docker_status
    echo "  ${CYAN}1)${RESET} Install Docker Engine"
    echo "  ${CYAN}2)${RESET} Add user to docker group"
    echo "  ${CYAN}3)${RESET} Test Docker (hello-world)"
    echo "  ${CYAN}4)${RESET} Manage Docker service (start/stop/enable)"
    echo "  ${CYAN}5)${RESET} Create example docker-compose.yml"
    echo "  ${CYAN}e)${RESET} Show environment info"
    print_menu_separator
    echo "  ${CYAN}0)${RESET} Exit"
    echo
    read -r -p "Choose: " c
    echo
    case "${c:-}" in
      1) install_docker || true; pause ;;
      2) add_user_docker_group || true; pause ;;
      3) test_docker || true; pause ;;
      4) manage_docker_service || true; pause ;;
      5) create_example_compose || true; pause ;;
      e|E) show_env_info; pause ;;
      0) log_info "Bye!"; exit 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

main "$@"
