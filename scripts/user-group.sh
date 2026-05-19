#!/usr/bin/env bash
# scripts/user-group.sh — User and group management
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
register_cleanup

SCRIPT_NAME="User & Group Manager"
SCRIPT_DESC="Create, modify, delete and inspect local users and groups"

handle_standard_args "$@"

# ---------------------------------------------------------------------------
# UI HELPERS
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# CHECKS / DISPLAY
# ---------------------------------------------------------------------------
require_account_tools() {
  local -a tools=("getent" "id")
  local missing=0
  local tool
  for tool in "${tools[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      log_warn "Missing required command: $tool"
      missing=1
    fi
  done
  [[ "$missing" -eq 0 ]]
}

require_shadow_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log_error "Required account command not found: $cmd"
    log_info "Install the system account tools package for your distribution."
    log_info "Debian/Ubuntu: passwd | Fedora/RHEL: shadow-utils | Arch: shadow | Alpine: shadow"
    return 1
  fi
}

show_user_details() {
  local username="$1"
  require_not_empty "$username" "Username"
  if ! user_exists "$username"; then
    log_error "User not found: $username"
    return 1
  fi

  log_info "User details: $username"
  getent passwd "$username"
  echo
  id "$username"
  echo
  if command -v chage >/dev/null 2>&1; then
    chage -l "$username" 2>/dev/null || true
  fi
}

show_group_details() {
  local group="$1"
  require_not_empty "$group" "Group"
  if ! group_exists "$group"; then
    log_error "Group not found: $group"
    return 1
  fi

  log_info "Group details: $group"
  getent group "$group"
}

list_users() {
  log_info "Local users:"
  awk -F: '{
    type=($3 >= 1000 && $1 != "nobody") ? "regular" : "system";
    printf "%-24s UID=%-7s GID=%-7s TYPE=%-8s HOME=%-28s SHELL=%s\n", $1, $3, $4, type, $6, $7
  }' /etc/passwd | sort
}

list_regular_users() {
  log_info "Regular users (UID >= 1000, excluding nobody):"
  awk -F: '($3 >= 1000 && $1 != "nobody") {
    printf "%-24s UID=%-7s HOME=%-28s SHELL=%s\n", $1, $3, $6, $7
  }' /etc/passwd | sort
}

list_groups() {
  log_info "Groups:"
  awk -F: '{printf "%-28s GID=%-8s MEMBERS=%s\n", $1, $3, $4}' /etc/group | sort
}

list_sudo_admin_groups() {
  log_info "Likely admin groups:"
  local group
  for group in sudo wheel admin doas; do
    if group_exists "$group"; then
      getent group "$group"
    fi
  done
}

search_user() {
  local username
  username="$(ask_input "Username")"
  show_user_details "$username"
}

search_group() {
  local group
  group="$(ask_input "Group name")"
  show_group_details "$group"
}

# ---------------------------------------------------------------------------
# USER OPERATIONS
# ---------------------------------------------------------------------------
create_primary_group_if_needed() {
  local group="$1"
  [[ -z "$group" ]] && return 0
  if group_exists "$group"; then return 0; fi
  log_warn "Group does not exist: $group"
  if ask_confirm "Create group '$group'?"; then
    require_shadow_command groupadd
    run_cmd_sudo groupadd "$group"
    log_ok "Group created: $group"
  else
    return 1
  fi
}

create_user() {
  check_sudo || return 1
  require_account_tools
  require_shadow_command useradd

  local username
  username="$(ask_input "Username")"
  require_not_empty "$username" "Username"
  if ! valid_linux_name "$username"; then
    log_error "Invalid username. Use lowercase letters, digits, underscore or hyphen, starting with a letter/underscore."
    return 1
  fi
  if user_exists "$username"; then
    log_error "User already exists: $username"
    return 1
  fi

  local full_name shell home_dir primary_group extra_groups uid create_home set_password
  full_name="$(ask_input "Full name/comment (optional)" "")"
  shell="$(ask_input "Login shell" "/bin/bash")"
  home_dir="$(ask_input "Home directory (empty for default)" "")"
  primary_group="$(ask_input "Primary group (empty for default)" "")"
  extra_groups="$(ask_input "Extra groups, comma-separated (optional)" "")"
  uid="$(ask_input "Custom UID (optional)" "")"

  if [[ -n "$uid" && ! "$uid" =~ ^[0-9]+$ ]]; then
    log_error "UID must be numeric."
    return 1
  fi
  if [[ -n "$shell" && ! -x "$shell" ]]; then
    log_warn "Shell is not executable or does not exist: $shell"
    if ! ask_confirm "Use this shell anyway?"; then return 0; fi
  fi

  create_home="yes"
  ask_confirm_yes "Create home directory?" && create_home="yes" || create_home="no"
  set_password="yes"
  ask_confirm_yes "Set password after creation?" && set_password="yes" || set_password="no"

  [[ -n "$primary_group" ]] && create_primary_group_if_needed "$primary_group"

  local -a cmd=(useradd)
  [[ "$create_home" == "yes" ]] && cmd+=("-m") || cmd+=("-M")
  [[ -n "$shell" ]] && cmd+=("-s" "$shell")
  [[ -n "$home_dir" ]] && cmd+=("-d" "$home_dir")
  [[ -n "$full_name" ]] && cmd+=("-c" "$full_name")
  [[ -n "$primary_group" ]] && cmd+=("-g" "$primary_group")
  if [[ -n "$extra_groups" ]]; then
    extra_groups="${extra_groups// /}"
    cmd+=("-G" "$extra_groups")
  fi
  [[ -n "$uid" ]] && cmd+=("-u" "$uid")
  cmd+=("$username")

  log_info "Command: sudo ${cmd[*]}"
  if ! ask_confirm "Create user '$username'?"; then
    log_warn "Cancelled."
    return 0
  fi

  run_cmd_sudo "${cmd[@]}"
  log_ok "User created: $username"

  if [[ "$set_password" == "yes" ]]; then
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
      log_info "[DRY-RUN] Would run passwd for: $username"
    else
      sudo passwd "$username"
    fi
  fi

  show_user_details "$username" || true
}

delete_user() {
  check_sudo || return 1
  require_shadow_command userdel
  local username
  username="$(ask_input "Username to delete")"
  require_not_empty "$username" "Username"
  if ! user_exists "$username"; then
    log_error "User not found: $username"
    return 1
  fi

  show_user_details "$username" || true
  echo
  log_warn "Deleting a user may break services or file ownership."
  local remove_home="no"
  ask_confirm "Remove home directory and mail spool too (-r)?" && remove_home="yes"
  if ! ask_confirm "Delete user '$username'?"; then
    log_warn "Cancelled."
    return 0
  fi

  if [[ "$remove_home" == "yes" ]]; then
    run_cmd_sudo userdel -r "$username"
  else
    run_cmd_sudo userdel "$username"
  fi
  log_ok "User deleted: $username"
}

modify_user_menu() {
  check_sudo || return 1
  require_shadow_command usermod
  local username
  username="$(ask_input "Username to modify")"
  require_not_empty "$username" "Username"
  if ! user_exists "$username"; then
    log_error "User not found: $username"
    return 1
  fi

  while true; do
    show_user_details "$username" || true
    menu_select "Modify User: $username" "Back" \
      "1:Change full name/comment" \
      "2:Change login shell" \
      "3:Change home directory" \
      "4:Lock account" \
      "5:Unlock account" \
      "6:Set/change password" \
      "7:Rename user" \
      "8:Change expiry date" \
      "9:Expire password now"

    case "$REPLY" in
      1)
        local full_name
        full_name="$(ask_input "New full name/comment")"
        run_cmd_sudo usermod -c "$full_name" "$username"
        log_ok "Comment updated."
        pause
        ;;
      2)
        local shell
        shell="$(ask_input "New shell" "/bin/bash")"
        require_not_empty "$shell" "Shell"
        run_cmd_sudo usermod -s "$shell" "$username"
        log_ok "Shell updated."
        pause
        ;;
      3)
        local home_dir
        home_dir="$(ask_input "New home directory" "/home/${username}")"
        require_not_empty "$home_dir" "Home directory"
        if ask_confirm "Move existing home contents?"; then
          run_cmd_sudo usermod -d "$home_dir" -m "$username"
        else
          run_cmd_sudo usermod -d "$home_dir" "$username"
        fi
        log_ok "Home directory updated."
        pause
        ;;
      4)
        if ask_confirm "Lock account '$username'?"; then
          run_cmd_sudo usermod -L "$username"
          log_ok "Account locked."
        fi
        pause
        ;;
      5)
        if ask_confirm "Unlock account '$username'?"; then
          run_cmd_sudo usermod -U "$username"
          log_ok "Account unlocked."
        fi
        pause
        ;;
      6)
        if [[ "${DRY_RUN:-0}" == "1" ]]; then
          log_info "[DRY-RUN] Would run passwd for: $username"
        else
          sudo passwd "$username"
        fi
        pause
        ;;
      7)
        local new_username
        new_username="$(ask_input "New username")"
        require_not_empty "$new_username" "New username"
        if ! valid_linux_name "$new_username"; then log_error "Invalid username."; pause; continue; fi
        if user_exists "$new_username"; then log_error "User already exists: $new_username"; pause; continue; fi
        if ask_confirm "Rename '$username' to '$new_username'?"; then
          run_cmd_sudo usermod -l "$new_username" "$username"
          log_ok "User renamed: $username -> $new_username"
          username="$new_username"
        fi
        pause
        ;;
      8)
        local expire_date
        expire_date="$(ask_input "Expiry date (YYYY-MM-DD, empty to clear)" "")"
        if [[ -n "$expire_date" ]]; then
          run_cmd_sudo usermod -e "$expire_date" "$username"
        else
          run_cmd_sudo usermod -e "" "$username"
        fi
        log_ok "Expiry date updated."
        pause
        ;;
      9)
        require_shadow_command chage
        if ask_confirm "Force password change at next login for '$username'?"; then
          run_cmd_sudo chage -d 0 "$username"
          log_ok "Password expired."
        fi
        pause
        ;;
      0) return 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# GROUP OPERATIONS
# ---------------------------------------------------------------------------
create_group() {
  check_sudo || return 1
  require_shadow_command groupadd
  local group gid
  group="$(ask_input "Group name")"
  require_not_empty "$group" "Group"
  if ! valid_linux_name "$group"; then log_error "Invalid group name."; return 1; fi
  if group_exists "$group"; then log_error "Group already exists: $group"; return 1; fi

  gid="$(ask_input "Custom GID (optional)" "")"
  if [[ -n "$gid" && ! "$gid" =~ ^[0-9]+$ ]]; then
    log_error "GID must be numeric."
    return 1
  fi

  if [[ -n "$gid" ]]; then
    run_cmd_sudo groupadd -g "$gid" "$group"
  else
    run_cmd_sudo groupadd "$group"
  fi
  log_ok "Group created: $group"
  show_group_details "$group" || true
}

rename_group() {
  check_sudo || return 1
  require_shadow_command groupmod
  local group new_group
  group="$(ask_input "Current group name")"
  require_not_empty "$group" "Group"
  if ! group_exists "$group"; then log_error "Group not found: $group"; return 1; fi

  new_group="$(ask_input "New group name")"
  require_not_empty "$new_group" "New group"
  if ! valid_linux_name "$new_group"; then log_error "Invalid group name."; return 1; fi
  if group_exists "$new_group"; then log_error "Group already exists: $new_group"; return 1; fi

  if ask_confirm "Rename group '$group' to '$new_group'?"; then
    run_cmd_sudo groupmod -n "$new_group" "$group"
    log_ok "Group renamed: $group -> $new_group"
  fi
}

delete_group() {
  check_sudo || return 1
  require_shadow_command groupdel
  local group
  group="$(ask_input "Group to delete")"
  require_not_empty "$group" "Group"
  if ! group_exists "$group"; then log_error "Group not found: $group"; return 1; fi

  show_group_details "$group" || true
  log_warn "Deleting a group can break file ownership or service permissions."
  if ask_confirm "Delete group '$group'?"; then
    run_cmd_sudo groupdel "$group"
    log_ok "Group deleted: $group"
  fi
}

# ---------------------------------------------------------------------------
# MEMBERSHIP OPERATIONS
# ---------------------------------------------------------------------------
add_user_to_group() {
  check_sudo || return 1
  require_shadow_command usermod
  local username group
  username="$(ask_input "Username")"
  require_not_empty "$username" "Username"
  if ! user_exists "$username"; then log_error "User not found: $username"; return 1; fi

  group="$(ask_input "Group")"
  require_not_empty "$group" "Group"
  create_primary_group_if_needed "$group"

  run_cmd_sudo usermod -aG "$group" "$username"
  log_ok "Added '$username' to group '$group'."
  id "$username" || true
}

remove_user_from_group() {
  check_sudo || return 1
  local username group
  username="$(ask_input "Username")"
  require_not_empty "$username" "Username"
  if ! user_exists "$username"; then log_error "User not found: $username"; return 1; fi

  group="$(ask_input "Group to remove user from")"
  require_not_empty "$group" "Group"
  if ! group_exists "$group"; then log_error "Group not found: $group"; return 1; fi

  log_warn "Removing a group may immediately revoke access after next login/session refresh."
  if ! ask_confirm "Remove '$username' from '$group'?"; then return 0; fi

  if command -v gpasswd >/dev/null 2>&1; then
    run_cmd_sudo gpasswd -d "$username" "$group"
  elif command -v deluser >/dev/null 2>&1; then
    run_cmd_sudo deluser "$username" "$group"
  else
    log_error "Neither gpasswd nor deluser is available."
    return 1
  fi
  log_ok "Removed '$username' from '$group'."
  id "$username" || true
}

set_primary_group() {
  check_sudo || return 1
  require_shadow_command usermod
  local username group
  username="$(ask_input "Username")"
  require_not_empty "$username" "Username"
  if ! user_exists "$username"; then log_error "User not found: $username"; return 1; fi

  group="$(ask_input "New primary group")"
  require_not_empty "$group" "Group"
  if ! group_exists "$group"; then log_error "Group not found: $group"; return 1; fi

  if ask_confirm "Set '$group' as primary group for '$username'?"; then
    run_cmd_sudo usermod -g "$group" "$username"
    log_ok "Primary group updated."
    id "$username" || true
  fi
}

show_status() {
  echo
  if require_account_tools >/dev/null 2>&1; then
    log_ok "Account lookup tools available."
  else
    log_warn "Some account lookup tools are missing."
  fi
  if command -v useradd >/dev/null 2>&1; then
    log_ok "useradd: $(command -v useradd)"
  else
    log_warn "useradd not found."
  fi
  echo
}

# ---------------------------------------------------------------------------
# MENU
# ---------------------------------------------------------------------------
main_menu_choice() {
  menu_select "$SCRIPT_NAME" "Exit" \
    "1:List all users" \
    "2:List regular users" \
    "3:List groups" \
    "4:List admin groups" \
    "5:Show user details" \
    "6:Show group details" \
    "7:Add user" \
    "8:Modify user" \
    "9:Delete user" \
    "10:Create group" \
    "11:Rename group" \
    "12:Delete group" \
    "13:Add user to group" \
    "14:Remove user from group" \
    "15:Set primary group" \
    "e:Show environment info"
}

main() {
  while true; do
    print_script_header "$SCRIPT_NAME" "$SCRIPT_DESC"
    show_status
    main_menu_choice
    echo

    case "${REPLY:-}" in
      1) list_users || true; pause ;;
      2) list_regular_users || true; pause ;;
      3) list_groups || true; pause ;;
      4) list_sudo_admin_groups || true; pause ;;
      5) search_user || true; pause ;;
      6) search_group || true; pause ;;
      7) create_user || true; pause ;;
      8) modify_user_menu || true; pause ;;
      9) delete_user || true; pause ;;
      10) create_group || true; pause ;;
      11) rename_group || true; pause ;;
      12) delete_group || true; pause ;;
      13) add_user_to_group || true; pause ;;
      14) remove_user_from_group || true; pause ;;
      15) set_primary_group || true; pause ;;
      e|E) show_env_info; pause ;;
      0) log_info "Bye!"; exit 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

main "$@"
