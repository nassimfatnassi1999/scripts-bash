#!/usr/bin/env bash
# scripts/backup-restore.sh — Local backup and restore utility
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
register_cleanup

SCRIPT_NAME="Backup / Restore Manager"
SCRIPT_DESC="Create tar backups, restore archives, sync directories and verify checksums"

handle_standard_args "$@"

BACKUP_ROOT="${BACKUP_ROOT:-${HOME}/backups}"

install_backup_tools() {
  detect_package_manager || return 1
  case "$PKG_MANAGER" in
    apt) check_sudo || return 1; run_cmd_sudo apt-get update -y; run_cmd_sudo apt-get install -y tar gzip xz-utils rsync coreutils ;;
    dnf|yum) check_sudo || return 1; run_cmd_sudo "$PKG_MANAGER" install -y tar gzip xz rsync coreutils ;;
    pacman) check_sudo || return 1; run_cmd_sudo pacman -S --noconfirm tar gzip xz rsync coreutils ;;
    zypper) check_sudo || return 1; run_cmd_sudo zypper install -y tar gzip xz rsync coreutils ;;
    apk) check_sudo || return 1; run_cmd_sudo apk add tar gzip xz rsync coreutils ;;
    brew) run_cmd brew install gnu-tar gzip xz rsync coreutils ;;
    *) log_error "Unsupported package manager."; return 1 ;;
  esac
}

ensure_backup_root() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    log_info "[DRY-RUN] Would create backup root: $BACKUP_ROOT"
  else
    mkdir -p "$BACKUP_ROOT"
  fi
}

create_tar_backup() {
  require_command tar
  ensure_backup_root
  local src name dest parent base compression
  src="$(ask_input "Source file/directory to backup" "${HOME}")"
  require_not_empty "$src" "Source"
  [[ -e "$src" ]] || { log_error "Source not found: $src"; return 1; }
  name="$(ask_input "Backup name" "$(basename "$src")-$(date +'%Y%m%d_%H%M%S')")"
  menu_select "Compression" "Cancel" "1:gzip (.tar.gz)" "2:xz (.tar.xz)" "3:none (.tar)"
  case "$REPLY" in
    1) compression="gz"; dest="${BACKUP_ROOT}/${name}.tar.gz" ;;
    2) compression="xz"; dest="${BACKUP_ROOT}/${name}.tar.xz" ;;
    3) compression="none"; dest="${BACKUP_ROOT}/${name}.tar" ;;
    0) return 0 ;;
    *) log_warn "Invalid option."; return 1 ;;
  esac
  parent="$(cd "$(dirname "$src")" && pwd)"
  base="$(basename "$src")"
  log_info "Source: $src"
  log_info "Destination: $dest"
  if ! ask_confirm "Create backup?"; then return 0; fi
  case "$compression" in
    gz) run_cmd tar -C "$parent" -czf "$dest" "$base" ;;
    xz) run_cmd tar -C "$parent" -cJf "$dest" "$base" ;;
    none) run_cmd tar -C "$parent" -cf "$dest" "$base" ;;
  esac
  if [[ "${DRY_RUN:-0}" != "1" && -f "$dest" ]]; then
    sha256sum "$dest" > "${dest}.sha256"
    log_ok "Backup created: $dest"
    log_ok "Checksum created: ${dest}.sha256"
    ls -lh "$dest"
  fi
}

restore_tar_backup() {
  require_command tar
  local archive target
  archive="$(ask_input "Archive to restore")"
  require_not_empty "$archive" "Archive"
  [[ -f "$archive" ]] || { log_error "Archive not found: $archive"; return 1; }
  target="$(ask_input "Restore target directory" "$(pwd)/restore")"
  require_not_empty "$target" "Target"
  [[ -d "$target" ]] || run_cmd mkdir -p "$target"
  log_warn "Restore may overwrite files if paths already exist."
  if ! ask_confirm "Restore '$archive' into '$target'?"; then return 0; fi
  case "$archive" in
    *.tar.gz|*.tgz) run_cmd tar -xzf "$archive" -C "$target" ;;
    *.tar.xz|*.txz) run_cmd tar -xJf "$archive" -C "$target" ;;
    *.tar) run_cmd tar -xf "$archive" -C "$target" ;;
    *) log_error "Unsupported archive extension."; return 1 ;;
  esac
  log_ok "Restore completed: $target"
}

rsync_backup() {
  require_command rsync "Install rsync first."
  local src dest args=("-aHAX" "--info=progress2")
  src="$(ask_input "Source directory")"
  dest="$(ask_input "Destination directory")"
  require_not_empty "$src" "Source"
  require_not_empty "$dest" "Destination"
  [[ -d "$src" ]] || { log_error "Source directory not found: $src"; return 1; }
  if ask_confirm "Delete files in destination that no longer exist in source?"; then args+=("--delete"); fi
  if ask_confirm "Run rsync in dry-run mode?"; then args+=("--dry-run"); fi
  log_warn "Rsync can overwrite destination files."
  if ! ask_confirm "Run rsync backup?"; then return 0; fi
  run_cmd mkdir -p "$dest"
  run_cmd rsync "${args[@]}" "${src%/}/" "${dest%/}/"
}

list_backups() {
  ensure_backup_root
  log_info "Backup root: $BACKUP_ROOT"
  find "$BACKUP_ROOT" -maxdepth 2 -type f \( -name '*.tar' -o -name '*.tar.gz' -o -name '*.tar.xz' -o -name '*.sha256' \) -printf '%TY-%Tm-%Td %TH:%TM %s %p\n' 2>/dev/null | sort -r || true
}

verify_checksum() {
  local sumfile
  sumfile="$(ask_input "sha256 checksum file")"
  require_not_empty "$sumfile" "Checksum file"
  [[ -f "$sumfile" ]] || { log_error "Checksum file not found: $sumfile"; return 1; }
  run_cmd sha256sum -c "$sumfile"
}

prune_old_backups() {
  ensure_backup_root
  local days
  days="$(ask_input "Delete backups older than N days" "30")"
  [[ "$days" =~ ^[0-9]+$ ]] || { log_error "Invalid number."; return 1; }
  log_warn "This deletes backup archives under $BACKUP_ROOT older than $days days."
  find "$BACKUP_ROOT" -type f \( -name '*.tar' -o -name '*.tar.gz' -o -name '*.tar.xz' \) -mtime +"$days" -print
  if ask_confirm "Delete listed backup archives and matching .sha256 files?"; then
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
      log_info "[DRY-RUN] Would delete listed files."
    else
      while IFS= read -r file; do
        rm -f "$file" "${file}.sha256"
      done < <(find "$BACKUP_ROOT" -type f \( -name '*.tar' -o -name '*.tar.gz' -o -name '*.tar.xz' \) -mtime +"$days")
    fi
    log_ok "Prune completed."
  fi
}

main_menu_choice() {
  menu_select "$SCRIPT_NAME" "Exit" \
    "1:Install backup tools" \
    "2:Create tar backup" \
    "3:Restore tar backup" \
    "4:Rsync directory backup" \
    "5:List backups" \
    "6:Verify checksum" \
    "7:Prune old backups" \
    "e:Show environment info"
}

main() {
  while true; do
    print_script_header "$SCRIPT_NAME" "$SCRIPT_DESC"
    log_info "Backup root: $BACKUP_ROOT"
    main_menu_choice
    echo
    case "${REPLY:-}" in
      1) install_backup_tools || true; pause ;;
      2) create_tar_backup || true; pause ;;
      3) restore_tar_backup || true; pause ;;
      4) rsync_backup || true; pause ;;
      5) list_backups || true; pause ;;
      6) verify_checksum || true; pause ;;
      7) prune_old_backups || true; pause ;;
      e|E) show_env_info; pause ;;
      0) log_info "Bye!"; exit 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

main "$@"
