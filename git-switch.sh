#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="git-switch"

# ============================================
# CONFIGURATION - Edit these values
# ============================================
GITHUB_NAME=""
GITHUB_EMAIL=""
GITHUB_TOKEN="" 

GITLAB_NAME=""
GITLAB_EMAIL=""
GITLAB_TOKEN=""  
# ============================================

usage() {
  cat <<'EOF'
Usage:
  git-switch.sh

Interactive helper to switch between GitHub and GitLab git configurations.
It can:
  - Set git user.name and user.email
  - Configure credential helper to use personal access tokens
  - Switch between GitHub and GitLab authentication
EOF
}

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: $cmd is not installed or not in PATH." >&2
    exit 1
  fi
}

prompt() {
  local label="$1"
  local var
  read -r -p "$label" var
  echo "$var"
}

confirm() {
  local label="$1"
  local answer
  read -r -p "$label (y/n): " answer
  [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}

set_git_identity() {
  local name="$1"
  local email="$2"

  git config --global user.name "$name"
  git config --global user.email "$email"
}

configure_git_credential_helper() {
  # Use the built-in credential storage
  git config --global credential.helper store
}

setup_github_credentials() {
  local username="$1"
  local token="$2"
  local credentials_file="$HOME/.git-credentials"

  # Remove old GitHub entries
  if [[ -f "$credentials_file" ]]; then
    sed -i.bak '/github\.com/d' "$credentials_file"
  fi

  # Add GitHub token with username
  if [[ -n "$token" ]]; then
    echo "https://${username}:${token}@github.com" >> "$credentials_file"
    chmod 600 "$credentials_file"
  fi
}

setup_gitlab_credentials() {
  local username="$1"
  local token="$2"
  local credentials_file="$HOME/.git-credentials"

  # Remove old GitLab entries
  if [[ -f "$credentials_file" ]]; then
    sed -i.bak '/gitlab\.com/d' "$credentials_file"
  fi

  # Add GitLab token (using username:token format)
  if [[ -n "$token" ]]; then
    echo "https://${username}:${token}@gitlab.com" >> "$credentials_file"
    chmod 600 "$credentials_file"
  fi
}

configure_provider() {
  local provider="$1"
  local name="$2"
  local email="$3"
  local token="$4"
  local username="$5"

  echo ""
  echo "Switching to $provider configuration..."

  if [[ -z "$token" ]]; then
    echo "⚠️  Warning: No token configured for $provider"
    echo "Please add your token to the script configuration section."
    echo ""
    if confirm "Do you want to enter the token now?"; then
      token=$(prompt "Enter your $provider Personal Access Token: ")
    else
      return
    fi
  fi

  set_git_identity "$name" "$email"
  echo "✓ Git identity set: $name <$email>"

  configure_git_credential_helper

  if [[ "$provider" == "GitHub" ]]; then
    setup_github_credentials "$username" "$token"
    echo "✓ GitHub credentials configured"
    echo "✓ Authentication configured - no password will be asked on push/pull"
    echo ""
    echo "You can now push/pull to GitHub repositories using HTTPS URLs"
  else
    setup_gitlab_credentials "$username" "$token"
    echo "✓ GitLab credentials configured"
    echo "✓ Authentication configured - no password will be asked on push/pull"
    echo ""
    echo "You can now push/pull to GitLab repositories using HTTPS URLs"
  fi

  echo ""
  echo "Current git config:"
  echo "  user.name  : $(git config --global user.name)"
  echo "  user.email : $(git config --global user.email)"
  echo ""
}

main_menu() {
  echo ""
  echo "==================================="
  echo "       Git Configuration Switcher"
  echo "==================================="
  echo "1) Switch to GitHub  ($GITHUB_EMAIL)"
  echo "2) Switch to GitLab  ($GITLAB_EMAIL)"
  echo "3) Show current git config"
  echo "4) Update tokens"
  echo "5) Exit"
  echo "==================================="
}

show_current_config() {
  echo ""
  echo "--- Current Git Configuration ---"
  echo "user.name  : $(git config --global user.name 2>/dev/null || echo 'Not set')"
  echo "user.email : $(git config --global user.email 2>/dev/null || echo 'Not set')"
  echo "credential.helper : $(git config --global credential.helper 2>/dev/null || echo 'Not set')"
  echo ""
  
  if [[ -f "$HOME/.git-credentials" ]]; then
    echo "Configured credentials:"
    grep -o 'https://[^@]*@[^/]*' "$HOME/.git-credentials" | sed 's/@/ -> /' | sed 's/https:\/\/[^:]*:/  [TOKEN] -> /' || echo "  None"
  fi
  echo ""
}

update_tokens() {
  echo ""
  echo "--- Update Tokens ---"
  echo "1) Update GitHub token"
  echo "2) Update GitLab token"
  echo "3) Back to main menu"
  
  local choice
  choice=$(prompt "Select an option [1-3]: ")

  case "$choice" in
    1)
      GITHUB_TOKEN=$(prompt "Enter your GitHub Personal Access Token: ")
      echo "✓ GitHub token updated in memory"
      echo "⚠️  Remember to update the script file to persist this change"
      ;;
    2)
      GITLAB_TOKEN=$(prompt "Enter your GitLab Personal Access Token: ")
      echo "✓ GitLab token updated in memory"
      echo "⚠️  Remember to update the script file to persist this change"
      ;;
    3)
      return
      ;;
    *)
      echo "Invalid option."
      ;;
  esac
}

main() {
  require_command git

  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  while true; do
    main_menu
    local choice
    choice=$(prompt "Select an option [1-5]: ")

    case "$choice" in
      1)
        configure_provider "GitHub" "$GITHUB_NAME" "$GITHUB_EMAIL" "$GITHUB_TOKEN" "$GITHUB_NAME"
        ;;
      2)
        configure_provider "GitLab" "$GITLAB_NAME" "$GITLAB_EMAIL" "$GITLAB_TOKEN" "$GITLAB_NAME"
        ;;
      3)
        show_current_config
        ;;
      4)
        update_tokens
        ;;
      5)
        echo "Bye!"
        exit 0
        ;;
      *)
        echo "Invalid option. Please choose 1-5."
        ;;
    esac
  done
}

main "$@"
