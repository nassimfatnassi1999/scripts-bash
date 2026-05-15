#!/usr/bin/env bash
# scripts/git-switch.sh — Git account switcher (GitHub / GitLab / custom)
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
register_cleanup

SCRIPT_NAME="Git Account Switcher"
SCRIPT_DESC="Switch between GitHub, GitLab or custom Git identities and credentials"

handle_standard_args "$@"

CREDENTIALS_FILE="${HOME}/.git-credentials"
CONFIG_FILE="${XDG_CONFIG_HOME:-${HOME}/.config}/git-switch/profiles.env"

# ---------------------------------------------------------------------------
# PROFILE MANAGEMENT
# ---------------------------------------------------------------------------
load_profiles() {
  if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE" || true
  fi
}

save_profiles() {
  local config_dir
  config_dir="$(dirname "$CONFIG_FILE")"
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    log_info "[DRY-RUN] Would create config directory: $config_dir"
    log_info "[DRY-RUN] Would write profiles file: $CONFIG_FILE"
    return 0
  fi
  mkdir -p "$config_dir"
  cat > "$CONFIG_FILE" <<EOF
# git-switch profile configuration — $(date)
GITHUB_NAME="${GITHUB_NAME:-}"
GITHUB_EMAIL="${GITHUB_EMAIL:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

GITLAB_NAME="${GITLAB_NAME:-}"
GITLAB_EMAIL="${GITLAB_EMAIL:-}"
GITLAB_TOKEN="${GITLAB_TOKEN:-}"

CUSTOM_NAME="${CUSTOM_NAME:-}"
CUSTOM_EMAIL="${CUSTOM_EMAIL:-}"
CUSTOM_TOKEN="${CUSTOM_TOKEN:-}"
CUSTOM_HOST="${CUSTOM_HOST:-}"
EOF
  chmod 600 "$CONFIG_FILE"
  log_ok "Profiles saved: $CONFIG_FILE"
}

# Default (empty) profile values
GITHUB_NAME="${GITHUB_NAME:-}"
GITHUB_EMAIL="${GITHUB_EMAIL:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
GITLAB_NAME="${GITLAB_NAME:-}"
GITLAB_EMAIL="${GITLAB_EMAIL:-}"
GITLAB_TOKEN="${GITLAB_TOKEN:-}"
CUSTOM_NAME="${CUSTOM_NAME:-}"
CUSTOM_EMAIL="${CUSTOM_EMAIL:-}"
CUSTOM_TOKEN="${CUSTOM_TOKEN:-}"
CUSTOM_HOST="${CUSTOM_HOST:-}"

load_profiles

# ---------------------------------------------------------------------------
# GIT OPERATIONS
# ---------------------------------------------------------------------------
set_git_identity() {
  local name="$1"
  local email="$2"
  git config --global user.name "$name"
  git config --global user.email "$email"
  log_ok "Git identity set: $name <$email>"
}

set_credential_helper() {
  git config --global credential.helper store
  log_ok "Credential helper set to: store"
}

write_credential() {
  local host="$1"
  local username="$2"
  local token="$3"

  [[ -z "$token" ]] && return 0

  # Remove existing entry for this host
  if [[ -f "$CREDENTIALS_FILE" ]]; then
    sed -i.bak "/${host}/d" "$CREDENTIALS_FILE"
  fi

  # Append new credential (token never echoed to terminal)
  printf 'https://%s:%s@%s\n' "$username" "$token" "$host" >> "$CREDENTIALS_FILE"
  chmod 600 "$CREDENTIALS_FILE"
  log_ok "Credentials stored for: $host"
}

switch_to_github() {
  local name="$GITHUB_NAME"
  local email="$GITHUB_EMAIL"
  local token="$GITHUB_TOKEN"

  [[ -z "$name" || -z "$email" ]] && {
    log_warn "GitHub profile not configured. Enter details now:"
    name="$(ask_input "GitHub name")"
    email="$(ask_input "GitHub email")"
    GITHUB_NAME="$name"
    GITHUB_EMAIL="$email"
  }

  if [[ -z "$token" ]]; then
    log_warn "GitHub token not set."
    if ask_confirm "Enter GitHub Personal Access Token now?"; then
      token="$(ask_secret "GitHub PAT (input hidden)")"
      GITHUB_TOKEN="$token"
    else
      log_warn "Skipping token. You will be prompted on push/pull."
    fi
  fi

  set_git_identity "$name" "$email"
  set_credential_helper
  [[ -n "$token" ]] && write_credential "github.com" "$name" "$token"
  save_profiles
  log_ok "Switched to GitHub: $name <$email>"
}

switch_to_gitlab() {
  local name="$GITLAB_NAME"
  local email="$GITLAB_EMAIL"
  local token="$GITLAB_TOKEN"

  [[ -z "$name" || -z "$email" ]] && {
    log_warn "GitLab profile not configured. Enter details now:"
    name="$(ask_input "GitLab name")"
    email="$(ask_input "GitLab email")"
    GITLAB_NAME="$name"
    GITLAB_EMAIL="$email"
  }

  if [[ -z "$token" ]]; then
    log_warn "GitLab token not set."
    if ask_confirm "Enter GitLab Personal Access Token now?"; then
      token="$(ask_secret "GitLab PAT (input hidden)")"
      GITLAB_TOKEN="$token"
    fi
  fi

  set_git_identity "$name" "$email"
  set_credential_helper
  [[ -n "$token" ]] && write_credential "gitlab.com" "$name" "$token"
  save_profiles
  log_ok "Switched to GitLab: $name <$email>"
}

switch_to_custom() {
  local name="$CUSTOM_NAME"
  local email="$CUSTOM_EMAIL"
  local token="$CUSTOM_TOKEN"
  local host="$CUSTOM_HOST"

  [[ -z "$host" ]] && host="$(ask_input "Custom Git host (e.g., gitlab.mycompany.com)")"
  [[ -z "$name" ]] && name="$(ask_input "Name")"
  [[ -z "$email" ]] && email="$(ask_input "Email")"

  if [[ -z "$token" ]]; then
    if ask_confirm "Enter Personal Access Token for $host?"; then
      token="$(ask_secret "PAT for $host (input hidden)")"
    fi
  fi

  CUSTOM_NAME="$name"
  CUSTOM_EMAIL="$email"
  CUSTOM_TOKEN="$token"
  CUSTOM_HOST="$host"

  set_git_identity "$name" "$email"
  set_credential_helper
  [[ -n "$token" ]] && write_credential "$host" "$name" "$token"
  save_profiles
  log_ok "Switched to custom host: $name <$email> @ $host"
}

# ---------------------------------------------------------------------------
# STATUS
# ---------------------------------------------------------------------------
show_current_config() {
  echo
  log_info "=== Current Git Configuration ==="
  echo "  user.name        : $(git config --global user.name 2>/dev/null || echo 'Not set')"
  echo "  user.email       : $(git config --global user.email 2>/dev/null || echo 'Not set')"
  echo "  credential.helper: $(git config --global credential.helper 2>/dev/null || echo 'Not set')"
  echo
  if [[ -f "$CREDENTIALS_FILE" ]]; then
    log_info "Stored credentials (hosts only, tokens hidden):"
    # Show only the host part, never the token
    grep -oP 'https://[^:]+:\K[^@]+(?=@)' "$CREDENTIALS_FILE" 2>/dev/null | \
      while IFS= read -r _; do echo "  [token hidden]"; done || true
    grep -oP 'https://[^:@]+@\K[^\n]+' "$CREDENTIALS_FILE" 2>/dev/null | \
      sed 's/^/  Host: /' || true
  fi
  echo
  log_info "=== Saved Profiles ==="
  echo "  GitHub : ${GITHUB_NAME:-<not set>} <${GITHUB_EMAIL:-}>"
  echo "  GitLab : ${GITLAB_NAME:-<not set>} <${GITLAB_EMAIL:-}>"
  echo "  Custom : ${CUSTOM_NAME:-<not set>} <${CUSTOM_EMAIL:-}> @ ${CUSTOM_HOST:-}"
}

# ---------------------------------------------------------------------------
# CONFIGURE PROFILES
# ---------------------------------------------------------------------------
configure_github_profile() {
  log_info "Configure GitHub profile:"
  GITHUB_NAME="$(ask_input "GitHub user name" "$GITHUB_NAME")"
  GITHUB_EMAIL="$(ask_input "GitHub email" "$GITHUB_EMAIL")"
  if ask_confirm "Update GitHub token?"; then
    GITHUB_TOKEN="$(ask_secret "GitHub Personal Access Token (input hidden)")"
  fi
  save_profiles
  log_ok "GitHub profile saved."
}

configure_gitlab_profile() {
  log_info "Configure GitLab profile:"
  GITLAB_NAME="$(ask_input "GitLab user name" "$GITLAB_NAME")"
  GITLAB_EMAIL="$(ask_input "GitLab email" "$GITLAB_EMAIL")"
  if ask_confirm "Update GitLab token?"; then
    GITLAB_TOKEN="$(ask_secret "GitLab Personal Access Token (input hidden)")"
  fi
  save_profiles
  log_ok "GitLab profile saved."
}

configure_custom_profile() {
  log_info "Configure custom Git profile:"
  CUSTOM_HOST="$(ask_input "Git host" "${CUSTOM_HOST:-gitlab.example.com}")"
  CUSTOM_NAME="$(ask_input "User name" "$CUSTOM_NAME")"
  CUSTOM_EMAIL="$(ask_input "Email" "$CUSTOM_EMAIL")"
  if ask_confirm "Update token?"; then
    CUSTOM_TOKEN="$(ask_secret "Personal Access Token (input hidden)")"
  fi
  save_profiles
  log_ok "Custom profile saved."
}

clear_credentials() {
  if [[ -f "$CREDENTIALS_FILE" ]]; then
    if ask_confirm "Clear ALL stored git credentials in $CREDENTIALS_FILE?"; then
      backup_file "$CREDENTIALS_FILE"
      > "$CREDENTIALS_FILE"
      chmod 600 "$CREDENTIALS_FILE"
      log_ok "Credentials cleared."
    fi
  else
    log_info "No credentials file found."
  fi
}

# ---------------------------------------------------------------------------
# MENU
# ---------------------------------------------------------------------------
main() {
  require_command git

  while true; do
    print_script_header "$SCRIPT_NAME" "$SCRIPT_DESC"
    show_current_config
    echo
    echo "  ${BOLD}${YELLOW}Switch Identity${RESET}"
    echo "  ${CYAN}1)${RESET} Switch to GitHub"
    echo "  ${CYAN}2)${RESET} Switch to GitLab"
    echo "  ${CYAN}3)${RESET} Switch to custom host"
    print_menu_separator
    echo "  ${BOLD}${YELLOW}Configure Profiles${RESET}"
    echo "  ${CYAN}4)${RESET} Configure GitHub profile"
    echo "  ${CYAN}5)${RESET} Configure GitLab profile"
    echo "  ${CYAN}6)${RESET} Configure custom host profile"
    print_menu_separator
    echo "  ${CYAN}7)${RESET} Clear all stored credentials"
    echo "  ${CYAN}e)${RESET} Show environment info"
    echo "  ${CYAN}0)${RESET} Exit"
    echo
    read -r -p "Choose: " c
    echo
    case "${c:-}" in
      1) switch_to_github || true; pause ;;
      2) switch_to_gitlab || true; pause ;;
      3) switch_to_custom || true; pause ;;
      4) configure_github_profile || true; pause ;;
      5) configure_gitlab_profile || true; pause ;;
      6) configure_custom_profile || true; pause ;;
      7) clear_credentials || true; pause ;;
      e|E) show_env_info; pause ;;
      0) log_info "Bye!"; exit 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

main "$@"
