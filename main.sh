#!/usr/bin/env bash
# main.sh — Central DevOps Toolbox Menu
# Usage: ./main.sh [--dry-run] [--check-env] [--help]

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

register_cleanup

SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

export DRY_RUN="${DRY_RUN:-0}"

usage() {
  cat <<EOF
${BOLD}Usage:${RESET} $0 [options]

${BOLD}Options:${RESET}
  --dry-run   Enable dry-run mode (no changes made)
  --check-env Show environment information and exit
  --help      Show this help message

${BOLD}Description:${RESET}
  Central menu for the Linux DevOps Toolbox.
  Provides access to all category scripts.
EOF
}

parse_args() {
  for arg in "$@"; do
    case "$arg" in
      --dry-run) export DRY_RUN=1 ;;
      --check-env) show_env_info; exit 0 ;;
      --help|-h) usage; exit 0 ;;
      *) log_warn "Unknown argument: $arg" ;;
    esac
  done
}

run_script() {
  local script="$1"
  local path="${SCRIPTS_DIR}/${script}"
  if [[ ! -f "$path" ]]; then
    log_error "Script not found: $path"
    pause
    return 1
  fi
  if [[ ! -x "$path" ]]; then
    log_warn "Script not executable: $path — fixing..."
    chmod +x "$path"
  fi
  echo
  log_step "Launching: $script"
  echo
  bash "$path" || true
}

# ---------------------------------------------------------------------------
# CATEGORY MENUS
# ---------------------------------------------------------------------------

menu_system() {
  while true; do
    print_script_header "SYSTEM" "System management tools"
    echo "  ${CYAN}1)${RESET} System Update          ${DIM}(system-update.sh)${RESET}"
    echo "  ${CYAN}2)${RESET} User & Group Mgmt      ${DIM}(user-group.sh)${RESET}"
    echo "  ${CYAN}3)${RESET} Service Manager        ${DIM}(service-manager.sh)${RESET}"
    echo "  ${CYAN}4)${RESET} Installed Packages      ${DIM}(installed-packages.sh)${RESET}"
    echo "  ${CYAN}5)${RESET} Dev Setup (Linux)      ${DIM}(setup-dev-linux.sh)${RESET}"
    echo "  ${CYAN}6)${RESET} Dev Tools Install      ${DIM}(dev-tools.sh)${RESET}"
    echo "  ${CYAN}7)${RESET} VM Tools               ${DIM}(vm-tools.sh)${RESET}"
    print_menu_separator
    echo "  ${CYAN}0)${RESET} Back to main menu"
    echo
    read -r -p "Choose: " c
    case "${c:-}" in
      1) run_script "system-update.sh"; pause ;;
      2) run_script "user-group.sh"; pause ;;
      3) run_script "service-manager.sh"; pause ;;
      4) run_script "installed-packages.sh"; pause ;;
      5) run_script "setup-dev-linux.sh"; pause ;;
      6) run_script "dev-tools.sh"; pause ;;
      7) run_script "vm-tools.sh"; pause ;;
      0) return 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

menu_docker() {
  while true; do
    print_script_header "DOCKER" "Docker management tools"
    echo "  ${CYAN}1)${RESET} Install Docker          ${DIM}(docker.sh)${RESET}"
    echo "  ${CYAN}2)${RESET} Docker Cleanup & Audit  ${DIM}(docker-cleanup.sh)${RESET}"
    print_menu_separator
    echo "  ${CYAN}0)${RESET} Back to main menu"
    echo
    read -r -p "Choose: " c
    case "${c:-}" in
      1) run_script "docker.sh"; pause ;;
      2) run_script "docker-cleanup.sh"; pause ;;
      0) return 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

menu_kubernetes() {
  while true; do
    print_script_header "KUBERNETES" "Kubernetes management tools"
    echo "  ${CYAN}1)${RESET} kubectl manager         ${DIM}(kubectl.sh)${RESET}"
    echo "  ${CYAN}2)${RESET} Minikube manager        ${DIM}(minikube.sh)${RESET}"
    echo "  ${CYAN}3)${RESET} Helm manager            ${DIM}(helm.sh)${RESET}"
    echo "  ${CYAN}4)${RESET} K8s Extra Tools         ${DIM}(k8s-tools.sh)${RESET}"
    print_menu_separator
    echo "  ${CYAN}0)${RESET} Back to main menu"
    echo
    read -r -p "Choose: " c
    case "${c:-}" in
      1) run_script "kubectl.sh"; pause ;;
      2) run_script "minikube.sh"; pause ;;
      3) run_script "helm.sh"; pause ;;
      4) run_script "k8s-tools.sh"; pause ;;
      0) return 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

menu_cloud() {
  while true; do
    print_script_header "CLOUD" "Cloud CLI tools (AWS / Azure / GCP)"
    echo "  ${CYAN}1)${RESET} Cloud CLI Manager       ${DIM}(cloud-cli.sh)${RESET}"
    print_menu_separator
    echo "  ${CYAN}0)${RESET} Back to main menu"
    echo
    read -r -p "Choose: " c
    case "${c:-}" in
      1) run_script "cloud-cli.sh"; pause ;;
      0) return 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

menu_iac() {
  while true; do
    print_script_header "INFRASTRUCTURE AS CODE" "IaC tools (Terraform / Ansible)"
    echo "  ${CYAN}1)${RESET} Terraform / OpenTofu    ${DIM}(terraform.sh)${RESET}"
    echo "  ${CYAN}2)${RESET} Ansible                 ${DIM}(ansible.sh)${RESET}"
    print_menu_separator
    echo "  ${CYAN}0)${RESET} Back to main menu"
    echo
    read -r -p "Choose: " c
    case "${c:-}" in
      1) run_script "terraform.sh"; pause ;;
      2) run_script "ansible.sh"; pause ;;
      0) return 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

menu_cicd() {
  while true; do
    print_script_header "CI/CD" "Continuous Integration / Delivery"
    echo "  ${CYAN}1)${RESET} Jenkins                 ${DIM}(jenkins.sh)${RESET}"
    print_menu_separator
    echo "  ${CYAN}0)${RESET} Back to main menu"
    echo
    read -r -p "Choose: " c
    case "${c:-}" in
      1) run_script "jenkins.sh"; pause ;;
      0) return 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

menu_backup() {
  while true; do
    print_script_header "BACKUP & RESTORE" "Backup and restore tools"
    echo "  ${CYAN}1)${RESET} Backup / Restore        ${DIM}(backup-restore.sh)${RESET}"
    echo "  ${CYAN}2)${RESET} Kopia Backup Manager    ${DIM}(kopia.sh)${RESET}"
    echo "  ${CYAN}3)${RESET} Zip/Disk Archiver       ${DIM}(zip-disk.sh)${RESET}"
    print_menu_separator
    echo "  ${CYAN}0)${RESET} Back to main menu"
    echo
    read -r -p "Choose: " c
    case "${c:-}" in
      1) run_script "backup-restore.sh"; pause ;;
      2) run_script "kopia.sh"; pause ;;
      3) run_script "zip-disk.sh"; pause ;;
      0) return 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

menu_network() {
  while true; do
    print_script_header "NETWORK & SECURITY" "Network and security tools"
    echo "  ${CYAN}1)${RESET} Network Tools           ${DIM}(network-tools.sh)${RESET}"
    echo "  ${CYAN}2)${RESET} SSH Manager             ${DIM}(ssh-manager.sh)${RESET}"
    echo "  ${CYAN}3)${RESET} Firewall Manager        ${DIM}(firewall.sh)${RESET}"
    echo "  ${CYAN}4)${RESET} Secrets Manager         ${DIM}(secrets-manager.sh)${RESET}"
    echo "  ${CYAN}5)${RESET} Git Account Switcher    ${DIM}(git-switch.sh)${RESET}"
    print_menu_separator
    echo "  ${CYAN}0)${RESET} Back to main menu"
    echo
    read -r -p "Choose: " c
    case "${c:-}" in
      1) run_script "network-tools.sh"; pause ;;
      2) run_script "ssh-manager.sh"; pause ;;
      3) run_script "firewall.sh"; pause ;;
      4) run_script "secrets-manager.sh"; pause ;;
      5) run_script "git-switch.sh"; pause ;;
      0) return 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

menu_monitoring() {
  while true; do
    print_script_header "MONITORING" "Monitoring and observability"
    echo "  ${CYAN}1)${RESET} Monitoring Setup        ${DIM}(monitoring.sh)${RESET}"
    echo "  ${CYAN}2)${RESET} Troubleshoot System     ${DIM}(troubleshoot.sh)${RESET}"
    print_menu_separator
    echo "  ${CYAN}0)${RESET} Back to main menu"
    echo
    read -r -p "Choose: " c
    case "${c:-}" in
      1) run_script "monitoring.sh"; pause ;;
      2) run_script "troubleshoot.sh"; pause ;;
      0) return 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

menu_automation() {
  while true; do
    print_script_header "AUTOMATION" "Task automation tools"
    echo "  ${CYAN}1)${RESET} Cron Manager            ${DIM}(cron-manager.sh)${RESET}"
    print_menu_separator
    echo "  ${CYAN}0)${RESET} Back to main menu"
    echo
    read -r -p "Choose: " c
    case "${c:-}" in
      1) run_script "cron-manager.sh"; pause ;;
      0) return 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

show_main_menu() {
  print_script_header "Linux DevOps Toolbox" "Your central DevOps command center"
  echo "  ${BOLD}${YELLOW}CATEGORIES${RESET}"
  echo
  echo "  ${CYAN}1)${RESET}  System              ${DIM}update, users, services, packages${RESET}"
  echo "  ${CYAN}2)${RESET}  Docker              ${DIM}install, cleanup, audit${RESET}"
  echo "  ${CYAN}3)${RESET}  Kubernetes          ${DIM}kubectl, minikube, helm, k8s-tools${RESET}"
  echo "  ${CYAN}4)${RESET}  Cloud               ${DIM}AWS / Azure / GCP CLI${RESET}"
  echo "  ${CYAN}5)${RESET}  IaC                 ${DIM}Terraform, Ansible${RESET}"
  echo "  ${CYAN}6)${RESET}  CI/CD               ${DIM}Jenkins${RESET}"
  echo "  ${CYAN}7)${RESET}  Backup              ${DIM}backup-restore, kopia, zip${RESET}"
  echo "  ${CYAN}8)${RESET}  Network & Security  ${DIM}network, SSH, firewall, secrets${RESET}"
  echo "  ${CYAN}9)${RESET}  Monitoring          ${DIM}monitoring, troubleshoot${RESET}"
  echo "  ${CYAN}10)${RESET} Automation          ${DIM}cron${RESET}"
  print_menu_separator
  echo "  ${CYAN}e)${RESET}  Show environment info"
  echo "  ${CYAN}l)${RESET}  Run linter (lint.sh)"
  echo "  ${CYAN}0)${RESET}  Exit"
  echo
}

main() {
  parse_args "$@"

  while true; do
    show_main_menu
    read -r -p "Choose category: " c
    echo
    case "${c:-}" in
      1)  menu_system ;;
      2)  menu_docker ;;
      3)  menu_kubernetes ;;
      4)  menu_cloud ;;
      5)  menu_iac ;;
      6)  menu_cicd ;;
      7)  menu_backup ;;
      8)  menu_network ;;
      9)  menu_monitoring ;;
      10) menu_automation ;;
      e|E) show_env_info; pause ;;
      l|L)
        if [[ -f "${SCRIPT_DIR}/lint.sh" ]]; then
          bash "${SCRIPT_DIR}/lint.sh"
          pause
        else
          log_warn "lint.sh not found."
          pause
        fi
        ;;
      0) log_info "Goodbye!"; exit 0 ;;
      *) log_warn "Invalid option. Choose 0-10, e, or l."; pause ;;
    esac
  done
}

main "$@"
