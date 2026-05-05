#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# =====================================
# User & Group Management Interactive
# =====================================

# ---- Colors ----
if command -v tput >/dev/null 2>&1; then
  BOLD="$(tput bold)"; RESET="$(tput sgr0)"
  RED="$(tput setaf 1)"; GREEN="$(tput setaf 2)"; YELLOW="$(tput setaf 3)"; CYAN="$(tput setaf 6)"; MAGENTA="$(tput setaf 5)"
else
  BOLD=""; RESET=""; RED=""; GREEN=""; YELLOW=""; CYAN=""; MAGENTA=""
fi

ok()   { echo "${GREEN}${BOLD}[OK]${RESET} $*"; }
info() { echo "${CYAN}${BOLD}[i]${RESET} $*"; }
warn() { echo "${YELLOW}${BOLD}[!]${RESET} $*"; }
err()  { echo "${RED}${BOLD}[X]${RESET} $*" >&2; }

pause() { read -r -p "Press Enter to continue... " _; }

need_cmd() { command -v "$1" >/dev/null 2>&1; }

require_sudo() {
  if ! need_cmd sudo; then err "sudo not found."; exit 1; fi
  if ! sudo -n true 2>/dev/null; then
    info "Sudo required (you may be prompted)."
    sudo true
  fi
}

# ---- Validators ----
valid_name() {
  # Accept typical linux user/group name rules (simplified)
  [[ "${1:-}" =~ ^[a-z_][a-z0-9_-]*$ ]]
}

user_exists() { getent passwd "$1" >/dev/null 2>&1; }
group_exists(){ getent group  "$1" >/dev/null 2>&1; }

ask() {
  # ask "Prompt" "default"
  local prompt="$1" def="${2:-}"
  local v
  if [[ -n "$def" ]]; then
    read -r -p "$prompt [$def]: " v
    echo "${v:-$def}"
  else
    read -r -p "$prompt: " v
    echo "$v"
  fi
}

confirm() {
  local prompt="${1:-Are you sure?} (y/N): "
  local a
  read -r -p "$prompt" a
  [[ "${a:-}" == "y" || "${a:-}" == "Y" ]]
}

show_user() {
  local u="$1"
  if ! user_exists "$u"; then err "User '$u' not found."; return 1; fi
  info "User info: $u"
  getent passwd "$u"
  echo
  info "Groups:"
  id "$u"
}

show_group() {
  local g="$1"
  if ! group_exists "$g"; then err "Group '$g' not found."; return 1; fi
  info "Group info: $g"
  getent group "$g"
}

# =====================================
# USER operations
# =====================================
user_add() {
  require_sudo
  echo "Add new user (interactive)"
  echo "Examples:"
  echo "  username: nassim"
  echo "  home: /home/nassim"
  echo

  local username
  username="$(ask "Enter username (lowercase, ex: nassim)")"
  if [[ -z "$username" ]]; then err "Username empty."; return 1; fi
  if ! valid_name "$username"; then err "Invalid username format."; return 1; fi
  if user_exists "$username"; then err "User already exists: $username"; return 1; fi

  local full_name shell home_dir create_home password_now add_sudo primary_group extra_groups uid gid
  full_name="$(ask "Full name (optional, press Enter to skip)" "")"
  shell="$(ask "Login shell (ex: /bin/bash)" "/bin/bash")"
  home_dir="$(ask "Home directory (press Enter for default)" "")"
  create_home="$(ask "Create home directory? (y/N)" "y")"
  password_now="$(ask "Set password now? (y/N)" "y")"

  primary_group="$(ask "Primary group (press Enter for default)" "")"
  extra_groups="$(ask "Extra groups (comma-separated, ex: sudo,docker) (optional)" "")"
  uid="$(ask "Custom UID (optional, press Enter to skip)" "")"
  gid="$(ask "Custom GID (optional, press Enter to skip)" "")"

  # Build useradd command
  local cmd=(sudo useradd)

  if [[ "${create_home,,}" == "y" ]]; then cmd+=(-m); else cmd+=(-M); fi
  [[ -n "$shell" ]] && cmd+=(-s "$shell")
  [[ -n "$home_dir" ]] && cmd+=(-d "$home_dir")
  [[ -n "$full_name" ]] && cmd+=(-c "$full_name")

  if [[ -n "$primary_group" ]]; then
    if ! group_exists "$primary_group"; then
      warn "Primary group '$primary_group' does not exist. Create it? "
      if confirm "Create group '$primary_group'? (y/N): "; then
        sudo groupadd "$primary_group"
        ok "Group created: $primary_group"
      else
        err "Primary group doesn't exist. Aborting."
        return 1
      fi
    fi
    cmd+=(-g "$primary_group")
  fi

  if [[ -n "$extra_groups" ]]; then
    # Convert commas to commas without spaces
    extra_groups="${extra_groups// /}"
    cmd+=(-G "$extra_groups")
  fi

  [[ -n "$uid" ]] && cmd+=(-u "$uid")
  [[ -n "$gid" ]] && cmd+=(-g "$gid")

  cmd+=("$username")

  info "Command to run:"
  echo "  ${cmd[*]}"
  if ! confirm "Proceed with user creation? (y/N): "; then
    warn "Cancelled."
    return 0
  fi

  # shellcheck disable=SC2068
  ${cmd[@]}
  ok "User created: $username"

  if [[ "${password_now,,}" == "y" ]]; then
    info "Set password for $username"
    sudo passwd "$username"
  fi

  show_user "$username" || true
}

user_delete() {
  require_sudo
  local u
  u="$(ask "Enter username to delete (ex: nassim)")"
  if ! user_exists "$u"; then err "User not found: $u"; return 1; fi

  echo "Delete options:"
  echo "  1) Delete user only (keep home)"
  echo "  2) Delete user + remove home (-r)"
  local opt
  opt="$(ask "Choose option (1/2)" "1")"

  show_user "$u" || true
  if ! confirm "Really delete user '$u'? (y/N): "; then
    warn "Cancelled."
    return 0
  fi

  if [[ "$opt" == "2" ]]; then
    sudo userdel -r "$u"
    ok "User deleted (with home): $u"
  else
    sudo userdel "$u"
    ok "User deleted (home kept): $u"
  fi
}

user_modify() {
  require_sudo
  local u
  u="$(ask "Enter username to modify")"
  if ! user_exists "$u"; then err "User not found: $u"; return 1; fi

  echo "Modify user '$u':"
  echo "  1) Change full name (comment)"
  echo "  2) Change login shell"
  echo "  3) Change home directory (move optional)"
  echo "  4) Lock account"
  echo "  5) Unlock account"
  echo "  6) Set/Change password"
  echo "  7) Rename user"
  local c
  c="$(ask "Choose option (1-7)")"

  case "$c" in
    1)
      local fn; fn="$(ask "Enter new full name (ex: Nassim Fatnassi)")"
      sudo usermod -c "$fn" "$u"
      ok "Full name updated."
      ;;
    2)
      local sh; sh="$(ask "Enter new shell (ex: /bin/bash)" "/bin/bash")"
      sudo usermod -s "$sh" "$u"
      ok "Shell updated."
      ;;
    3)
      local nh mv
      nh="$(ask "Enter new home (ex: /home/$u)" "/home/$u")"
      mv="$(ask "Move content to new home? (y/N)" "y")"
      if [[ "${mv,,}" == "y" ]]; then
        sudo usermod -d "$nh" -m "$u"
      else
        sudo usermod -d "$nh" "$u"
      fi
      ok "Home updated."
      ;;
    4) sudo usermod -L "$u"; ok "Account locked." ;;
    5) sudo usermod -U "$u"; ok "Account unlocked." ;;
    6) sudo passwd "$u"; ok "Password updated." ;;
    7)
      local nu
      nu="$(ask "Enter new username")"
      if ! valid_name "$nu"; then err "Invalid name."; return 1; fi
      if user_exists "$nu"; then err "User already exists: $nu"; return 1; fi
      sudo usermod -l "$nu" "$u"
      ok "User renamed: $u -> $nu"
      u="$nu"
      ;;
    *) warn "Invalid choice." ;;
  esac

  show_user "$u" || true
}

# =====================================
# GROUP operations
# =====================================
group_add() {
  require_sudo
  local g
  g="$(ask "Enter group name to create (ex: devops)")"
  if [[ -z "$g" ]]; then err "Group name empty."; return 1; fi
  if ! valid_name "$g"; then err "Invalid group name format."; return 1; fi
  if group_exists "$g"; then err "Group already exists: $g"; return 1; fi

  local gid; gid="$(ask "Custom GID (optional, press Enter to skip)" "")"
  if [[ -n "$gid" ]]; then
    sudo groupadd -g "$gid" "$g"
  else
    sudo groupadd "$g"
  fi
  ok "Group created: $g"
  show_group "$g" || true
}

group_delete() {
  require_sudo
  local g
  g="$(ask "Enter group name to delete")"
  if ! group_exists "$g"; then err "Group not found: $g"; return 1; fi

  show_group "$g" || true
  if ! confirm "Really delete group '$g'? (y/N): "; then
    warn "Cancelled."
    return 0
  fi

  sudo groupdel "$g"
  ok "Group deleted: $g"
}

group_rename() {
  require_sudo
  local g ng
  g="$(ask "Enter current group name")"
  if ! group_exists "$g"; then err "Group not found: $g"; return 1; fi
  ng="$(ask "Enter new group name")"
  if ! valid_name "$ng"; then err "Invalid new group name."; return 1; fi
  if group_exists "$ng"; then err "Group already exists: $ng"; return 1; fi

  sudo groupmod -n "$ng" "$g"
  ok "Group renamed: $g -> $ng"
}

# =====================================
# Membership operations
# =====================================
add_user_to_group() {
  require_sudo
  local u g
  u="$(ask "Enter username (ex: nassim)")"
  if ! user_exists "$u"; then err "User not found: $u"; return 1; fi
  g="$(ask "Enter group name (ex: sudo)")"
  if ! group_exists "$g"; then
    warn "Group '$g' does not exist."
    if confirm "Create group '$g'? (y/N): "; then
      sudo groupadd "$g"
      ok "Group created: $g"
    else
      err "Group missing. Aborting."
      return 1
    fi
  fi

  sudo usermod -aG "$g" "$u"
  ok "Added user '$u' to group '$g'."
  id "$u"
}

remove_user_from_group() {
  require_sudo
  local u g
  u="$(ask "Enter username")"
  if ! user_exists "$u"; then err "User not found: $u"; return 1; fi
  g="$(ask "Enter group name to remove user from")"
  if ! group_exists "$g"; then err "Group not found: $g"; return 1; fi

  # gpasswd is simplest:
  sudo gpasswd -d "$u" "$g"
  ok "Removed user '$u' from group '$g'."
  id "$u"
}

set_primary_group() {
  require_sudo
  local u g
  u="$(ask "Enter username")"
  if ! user_exists "$u"; then err "User not found: $u"; return 1; fi
  g="$(ask "Enter new primary group")"
  if ! group_exists "$g"; then err "Group not found: $g"; return 1; fi

  sudo usermod -g "$g" "$u"
  ok "Primary group updated for '$u' -> '$g'"
  id "$u"
}

list_users() {
  info "Local users (UID >= 1000 usually):"
  awk -F: '($3>=1000)&&($1!="nobody"){printf "%-20s UID=%s HOME=%s SHELL=%s\n",$1,$3,$6,$7}' /etc/passwd | sort
}

list_groups() {
  info "Groups:"
  cut -d: -f1 /etc/group | sort
}

search_user() {
  local u
  u="$(ask "Enter username to show")"
  show_user "$u"
}

search_group() {
  local g
  g="$(ask "Enter group name to show")"
  show_group "$g"
}

# =====================================
# Menu
# =====================================
header() {
  clear || true
  echo "${BOLD}${MAGENTA}========================================${RESET}"
  echo "${BOLD}${MAGENTA}     User & Group Management Menu       ${RESET}"
  echo "${BOLD}${MAGENTA}========================================${RESET}"
  echo "Host: $(hostname) | User: $(whoami) | Date: $(date +'%F %T')"
  echo
}

menu() {
  echo "${BOLD}1) List users${RESET}"
  echo "${BOLD}2) List groups${RESET}"
  echo "${BOLD}3) Show user details${RESET}"
  echo "${BOLD}4) Show group details${RESET}"
  echo
  echo "${BOLD}5) Add user (interactive)${RESET}"
  echo "${BOLD}6) Modify user${RESET}"
  echo "${BOLD}7) Delete user${RESET}"
  echo
  echo "${BOLD}8) Create group${RESET}"
  echo "${BOLD}9) Rename group${RESET}"
  echo "${BOLD}10) Delete group${RESET}"
  echo
  echo "${BOLD}11) Add user to group${RESET}"
  echo "${BOLD}12) Remove user from group${RESET}"
  echo "${BOLD}13) Set user's primary group${RESET}"
  echo
  echo "${BOLD}0) Exit${RESET}"
  echo
}

main() {
  while true; do
    header
    menu
    read -r -p "Choose an option: " c
    echo
    case "${c:-}" in
      1) list_users; pause ;;
      2) list_groups; pause ;;
      3) search_user || true; pause ;;
      4) search_group || true; pause ;;
      5) user_add || true; pause ;;
      6) user_modify || true; pause ;;
      7) user_delete || true; pause ;;
      8) group_add || true; pause ;;
      9) group_rename || true; pause ;;
      10) group_delete || true; pause ;;
      11) add_user_to_group || true; pause ;;
      12) remove_user_from_group || true; pause ;;
      13) set_primary_group || true; pause ;;
      0) info "Bye."; exit 0 ;;
      *) warn "Invalid option."; pause ;;
    esac
  done
}

main