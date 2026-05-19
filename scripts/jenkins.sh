#!/usr/bin/env bash
# scripts/jenkins.sh — Jenkins CI/CD installer and manager
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
register_cleanup

SCRIPT_NAME="Jenkins Manager"
SCRIPT_DESC="Install and manage Jenkins CI/CD server"

handle_standard_args "$@"

JENKINS_PORT="${JENKINS_PORT:-8080}"
JENKINS_HOME="${JENKINS_HOME:-/var/lib/jenkins}"

# ---------------------------------------------------------------------------
# STATUS
# ---------------------------------------------------------------------------
show_jenkins_status() {
  echo
  if is_installed jenkins || is_installed java; then
    if systemd_available && systemctl is-active --quiet jenkins 2>/dev/null; then
      log_ok "Jenkins service: RUNNING"
      log_ok "URL: http://localhost:${JENKINS_PORT}"
    elif is_installed java; then
      log_warn "Jenkins service: NOT running (Java installed)"
    else
      log_warn "Jenkins: NOT installed"
    fi
  else
    log_warn "Jenkins: NOT installed"
  fi
  if is_installed java; then
    log_ok "Java: $(java -version 2>&1 | head -1)"
  else
    log_warn "Java: NOT installed"
  fi
  echo
}

# ---------------------------------------------------------------------------
# INSTALL JAVA
# ---------------------------------------------------------------------------
install_java() {
  if is_installed java; then
    log_ok "Java already installed: $(java -version 2>&1 | head -1)"
    if ! ask_confirm "Reinstall Java?"; then return 0; fi
  fi

  check_sudo || return 1
  detect_package_manager || return 1

  local java_version
  java_version="$(ask_input "Java version to install" "17")"

  case "$PKG_MANAGER" in
    apt)
      run_cmd_sudo apt-get update -y || return 1
      run_cmd_sudo apt-get install -y "openjdk-${java_version}-jdk" || return 1
      ;;
    dnf|yum)
      install_packages "java-${java_version}-openjdk-devel" || return 1
      ;;
    pacman)
      run_cmd_sudo pacman -S --noconfirm jdk-openjdk || return 1
      ;;
    zypper)
      run_cmd_sudo zypper install -y "java-${java_version}-openjdk-devel" || return 1
      ;;
    apk)
      run_cmd_sudo apk add "openjdk${java_version}" || return 1
      ;;
    *)
      log_error "Cannot install Java automatically on this system."
      return 1
      ;;
  esac

  log_ok "Java installed: $(java -version 2>&1 | head -1)"
}

# ---------------------------------------------------------------------------
# INSTALL JENKINS
# ---------------------------------------------------------------------------
install_jenkins() {
  if systemd_available && systemctl is-active --quiet jenkins 2>/dev/null; then
    log_ok "Jenkins is already running."
    if ! ask_confirm "Reinstall Jenkins?"; then return 0; fi
  fi

  # Java is required
  if ! is_installed java; then
    log_warn "Java is not installed. Installing Java 17..."
    install_java || return 1
  fi

  require_internet
  check_sudo || return 1
  detect_package_manager || return 1

  JENKINS_PORT="$(ask_input "Jenkins HTTP port" "$JENKINS_PORT")"

  case "$PKG_MANAGER" in
    apt)
      _install_jenkins_apt || return 1
      ;;
    dnf|yum)
      _install_jenkins_rpm || return 1
      ;;
    *)
      _install_jenkins_war || return 1
      ;;
  esac

  # Configure port if non-default
  _configure_jenkins_port "$JENKINS_PORT" || return 1

  # Enable and start
  if systemd_available; then
    run_cmd_sudo systemctl enable --now jenkins || return 1
    log_ok "Jenkins service started."
  fi

  log_ok "Jenkins installed and running on port $JENKINS_PORT"
  log_info "URL: http://localhost:${JENKINS_PORT}"
  _show_initial_password
}

_install_jenkins_apt() {
  log_step "Installing Jenkins on Debian/Ubuntu..."
  run_cmd_sudo apt-get update -y || return 1
  run_cmd_sudo apt-get install -y curl gnupg || return 1

  local tmpdir; tmpdir="$(make_tmpdir)"
  download_file "https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key" "${tmpdir}/jenkins.key" || return 1
  run_cmd_sudo tee /usr/share/keyrings/jenkins-keyring.asc < "${tmpdir}/jenkins.key" > /dev/null || return 1
  echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
    | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null || return 1
  run_cmd_sudo apt-get update -y || return 1
  run_cmd_sudo apt-get install -y jenkins || return 1
}

_install_jenkins_rpm() {
  log_step "Installing Jenkins on Fedora/RHEL/CentOS..."
  local tmpdir; tmpdir="$(make_tmpdir)"
  download_file "https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key" "${tmpdir}/jenkins.key" || return 1
  run_cmd_sudo rpm --import "${tmpdir}/jenkins.key" || return 1
  cat > "${tmpdir}/jenkins.repo" <<'EOF'
[jenkins]
name=Jenkins-stable
baseurl=http://pkg.jenkins.io/redhat-stable
gpgcheck=1
EOF
  run_cmd_sudo mv "${tmpdir}/jenkins.repo" /etc/yum.repos.d/jenkins.repo || return 1
  install_packages jenkins || return 1
}

_install_jenkins_war() {
  log_step "Installing Jenkins via WAR file..."
  local tmpdir; tmpdir="$(make_tmpdir)"
  local jenkins_war="/opt/jenkins.war"
  download_file "https://get.jenkins.io/war-stable/latest/jenkins.war" "${tmpdir}/jenkins.war" || return 1
  run_cmd_sudo install -m 0644 "${tmpdir}/jenkins.war" "$jenkins_war" || return 1
  log_ok "Jenkins WAR downloaded: $jenkins_war"
  log_info "Start Jenkins with: java -jar $jenkins_war --httpPort=${JENKINS_PORT}"

  # Create systemd unit if available
  if systemd_available; then
    cat > "${tmpdir}/jenkins.service" <<EOF
[Unit]
Description=Jenkins CI Server
After=network.target

[Service]
Type=simple
User=jenkins
ExecStart=/usr/bin/java -jar ${jenkins_war} --httpPort=${JENKINS_PORT}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
    if ask_confirm "Install as systemd service?"; then
      run_cmd_sudo useradd -r -s /bin/false jenkins 2>/dev/null || true
      run_cmd_sudo mv "${tmpdir}/jenkins.service" /etc/systemd/system/jenkins.service || return 1
      run_cmd_sudo systemctl daemon-reload || return 1
    fi
  fi
}

_configure_jenkins_port() {
  local port="$1"
  [[ "$port" == "8080" ]] && return 0

  # Systemd override
  if systemd_available; then
    run_cmd_sudo mkdir -p /etc/systemd/system/jenkins.service.d
    local tmpdir; tmpdir="$(make_tmpdir)"
    cat > "${tmpdir}/jenkins-port.conf" <<EOF
[Service]
Environment="JENKINS_PORT=${port}"
EOF
    run_cmd_sudo mv "${tmpdir}/jenkins-port.conf" /etc/systemd/system/jenkins.service.d/port.conf || return 1
    run_cmd_sudo systemctl daemon-reload || return 1
    log_ok "Jenkins port configured: $port"
  fi
}

_show_initial_password() {
  local pass_file="${JENKINS_HOME}/secrets/initialAdminPassword"
  echo
  if [[ -f "$pass_file" ]]; then
    log_info "=== Jenkins Initial Admin Password ==="
    sudo cat "$pass_file" 2>/dev/null || cat "$pass_file" 2>/dev/null || true
    echo
    log_info "Use this password at: http://localhost:${JENKINS_PORT}"
  else
    log_info "Initial password file not found yet."
    log_info "Check: sudo cat $pass_file (after service starts)"
  fi
}

# ---------------------------------------------------------------------------
# SERVICE MANAGEMENT
# ---------------------------------------------------------------------------
manage_jenkins_service() {
  if ! systemd_available; then
    log_warn "systemd not available."
    return 0
  fi
  echo
  echo "  1) Start Jenkins"
  echo "  2) Stop Jenkins"
  echo "  3) Restart Jenkins"
  echo "  4) Show Jenkins status"
  echo "  5) Show Jenkins logs (last 50 lines)"
  echo "  6) Follow Jenkins logs"
  echo "  0) Back"
  echo
  read -r -p "Choose: " c
  case "${c:-}" in
    1) run_cmd_sudo systemctl start jenkins && log_ok "Jenkins started." ;;
    2) run_cmd_sudo systemctl stop jenkins && log_ok "Jenkins stopped." ;;
    3) run_cmd_sudo systemctl restart jenkins && log_ok "Jenkins restarted." ;;
    4) service_status jenkins ;;
    5) sudo journalctl -u jenkins -n 50 --no-pager || true ;;
    6)
      log_info "Press Ctrl+C to stop."
      sudo journalctl -u jenkins -f || true
      ;;
    0) return 0 ;;
    *) log_warn "Invalid option." ;;
  esac
}

show_initial_password() {
  _show_initial_password
}

# ---------------------------------------------------------------------------
# MENU
# ---------------------------------------------------------------------------
main() {
  while true; do
    print_script_header "$SCRIPT_NAME" "$SCRIPT_DESC"
    show_jenkins_status
    echo "  ${CYAN}1)${RESET} Install Java"
    echo "  ${CYAN}2)${RESET} Install Jenkins"
    echo "  ${CYAN}3)${RESET} Manage Jenkins service (start/stop/restart/logs)"
    echo "  ${CYAN}4)${RESET} Show initial admin password"
    echo "  ${CYAN}e)${RESET} Show environment info"
    print_menu_separator
    echo "  ${CYAN}0)${RESET} Exit"
    echo
    read -r -p "Choose: " c
    echo
    case "${c:-}" in
      1) install_java || true; pause ;;
      2) install_jenkins || true; pause ;;
      3) manage_jenkins_service || true; pause ;;
      4) show_initial_password || true; pause ;;
      e|E) show_env_info; pause ;;
      0) log_info "Bye!"; exit 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

main "$@"
