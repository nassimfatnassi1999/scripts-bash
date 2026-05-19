#!/usr/bin/env bash
# scripts/zip-disk.sh — Disk, folder and archive utility
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
register_cleanup

SCRIPT_NAME="Zip / Disk Archiver"
SCRIPT_DESC="Inspect disks, create archives, extract archives, and verify checksums"

handle_standard_args "$@"

SOURCE_PATH="${SOURCE_PATH:-}"
DEST_ARCHIVE="${DEST_ARCHIVE:-}"
ARCHIVE_FORMAT="${ARCHIVE_FORMAT:-zip}"

# ---------------------------------------------------------------------------
# UI HELPERS
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# DEPENDENCIES
# ---------------------------------------------------------------------------
install_archive_tools() {
  check_sudo || return 1
  detect_package_manager || return 1

  case "$PKG_MANAGER" in
    apt)
      run_cmd_sudo apt-get update -y
      run_cmd_sudo apt-get install -y zip unzip tar gzip bzip2 xz-utils coreutils
      ;;
    dnf)
      run_cmd_sudo dnf install -y zip unzip tar gzip bzip2 xz coreutils
      ;;
    yum)
      run_cmd_sudo yum install -y zip unzip tar gzip bzip2 xz coreutils
      ;;
    pacman)
      run_cmd_sudo pacman -S --noconfirm zip unzip tar gzip bzip2 xz coreutils
      ;;
    zypper)
      run_cmd_sudo zypper install -y zip unzip tar gzip bzip2 xz coreutils
      ;;
    apk)
      run_cmd_sudo apk add zip unzip tar gzip bzip2 xz coreutils
      ;;
    *)
      log_error "Unsupported package manager."
      return 1
      ;;
  esac
}

ensure_command_or_offer_install() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    return 0
  fi
  log_warn "Missing command: $cmd"
  if ask_confirm "Install archive tools now?"; then
    install_archive_tools
  fi
  require_command "$cmd"
}

# ---------------------------------------------------------------------------
# DISK INFO
# ---------------------------------------------------------------------------
show_disks() {
  log_info "=== Disks and partitions ==="
  if command -v lsblk >/dev/null 2>&1; then
    lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS,ROTA,TYPE 2>/dev/null || lsblk
  else
    log_warn "lsblk not available."
  fi
  echo
  log_info "=== Filesystem usage ==="
  df -hT 2>/dev/null || df -h
  echo
  log_info "=== Inode usage ==="
  df -i 2>/dev/null || true
}

show_source_size() {
  local path="${1:-$SOURCE_PATH}"
  require_not_empty "$path" "Source path"
  [[ ! -e "$path" ]] && { log_error "Path not found: $path"; return 1; }
  if command -v du >/dev/null 2>&1; then
    du -sh "$path"
  else
    log_warn "du not available."
  fi
}

# ---------------------------------------------------------------------------
# CONFIG
# ---------------------------------------------------------------------------
set_source() {
  show_disks || true
  echo
  local path
  path="$(ask_input "Source directory or file" "${SOURCE_PATH:-${HOME}}")"
  require_not_empty "$path" "Source"
  if [[ ! -e "$path" ]]; then
    log_error "Source does not exist: $path"
    return 1
  fi
  SOURCE_PATH="$path"
  log_ok "Source set: $SOURCE_PATH"
}

select_format() {
  menu_select "Archive Format" "Cancel" \
    "1:zip" \
    "2:tar.gz" \
    "3:tar.bz2" \
    "4:tar.xz"
  case "$REPLY" in
    1) ARCHIVE_FORMAT="zip" ;;
    2) ARCHIVE_FORMAT="tar.gz" ;;
    3) ARCHIVE_FORMAT="tar.bz2" ;;
    4) ARCHIVE_FORMAT="tar.xz" ;;
    0) return 0 ;;
    *) log_warn "Invalid option."; return 1 ;;
  esac
  log_ok "Archive format set: $ARCHIVE_FORMAT"
}

archive_extension() {
  case "$ARCHIVE_FORMAT" in
    zip) echo ".zip" ;;
    tar.gz) echo ".tar.gz" ;;
    tar.bz2) echo ".tar.bz2" ;;
    tar.xz) echo ".tar.xz" ;;
    *) echo ".archive" ;;
  esac
}

set_destination() {
  local default_name dest dir ext
  ext="$(archive_extension)"
  default_name="${HOME}/backup-$(date +'%Y%m%d_%H%M%S')${ext}"
  dest="$(ask_input "Destination archive path" "${DEST_ARCHIVE:-$default_name}")"
  require_not_empty "$dest" "Destination"

  case "$ARCHIVE_FORMAT" in
    zip) [[ "$dest" == *.zip ]] || dest="${dest}.zip" ;;
    tar.gz) [[ "$dest" == *.tar.gz || "$dest" == *.tgz ]] || dest="${dest}.tar.gz" ;;
    tar.bz2) [[ "$dest" == *.tar.bz2 || "$dest" == *.tbz2 ]] || dest="${dest}.tar.bz2" ;;
    tar.xz) [[ "$dest" == *.tar.xz || "$dest" == *.txz ]] || dest="${dest}.tar.xz" ;;
  esac

  dir="$(dirname "$dest")"
  if [[ ! -d "$dir" ]]; then
    if ask_confirm "Destination directory does not exist. Create '$dir'?"; then
      run_cmd mkdir -p "$dir"
    else
      log_warn "Cancelled."
      return 0
    fi
  fi

  if [[ -e "$dest" ]] && ! ask_confirm "Archive exists. Overwrite '$dest'?"; then
    log_warn "Cancelled."
    return 0
  fi

  DEST_ARCHIVE="$dest"
  log_ok "Destination set: $DEST_ARCHIVE"
}

show_current_config() {
  echo
  log_info "=== Current configuration ==="
  echo "  Source     : ${SOURCE_PATH:-<not set>}"
  echo "  Format     : ${ARCHIVE_FORMAT}"
  echo "  Destination: ${DEST_ARCHIVE:-<not set>}"
  echo
  [[ -n "${SOURCE_PATH:-}" && -e "$SOURCE_PATH" ]] && show_source_size "$SOURCE_PATH"
  echo
}

# ---------------------------------------------------------------------------
# ARCHIVE OPERATIONS
# ---------------------------------------------------------------------------
create_archive() {
  require_not_empty "${SOURCE_PATH:-}" "Source"
  require_not_empty "${DEST_ARCHIVE:-}" "Destination"
  [[ ! -e "$SOURCE_PATH" ]] && { log_error "Source not found: $SOURCE_PATH"; return 1; }

  if [[ -e "$DEST_ARCHIVE" ]]; then
    log_warn "Destination already exists: $DEST_ARCHIVE"
    if ! ask_confirm "Overwrite destination archive?"; then
      log_warn "Cancelled."
      return 0
    fi
  fi

  local parent base
  parent="$(cd "$(dirname "$SOURCE_PATH")" && pwd)"
  base="$(basename "$SOURCE_PATH")"

  log_info "Source     : $SOURCE_PATH"
  log_info "Destination: $DEST_ARCHIVE"
  log_info "Format     : $ARCHIVE_FORMAT"
  show_source_size "$SOURCE_PATH" || true
  echo

  if ! ask_confirm "Create archive now?"; then
    log_warn "Cancelled."
    return 0
  fi

  case "$ARCHIVE_FORMAT" in
    zip)
      ensure_command_or_offer_install zip
      run_cmd zip -r -y "$DEST_ARCHIVE" "$SOURCE_PATH"
      ;;
    tar.gz)
      ensure_command_or_offer_install tar
      run_cmd tar -C "$parent" -czf "$DEST_ARCHIVE" "$base"
      ;;
    tar.bz2)
      ensure_command_or_offer_install tar
      run_cmd tar -C "$parent" -cjf "$DEST_ARCHIVE" "$base"
      ;;
    tar.xz)
      ensure_command_or_offer_install tar
      run_cmd tar -C "$parent" -cJf "$DEST_ARCHIVE" "$base"
      ;;
    *)
      log_error "Unsupported archive format: $ARCHIVE_FORMAT"
      return 1
      ;;
  esac

  log_ok "Archive created: $DEST_ARCHIVE"
  [[ -f "$DEST_ARCHIVE" ]] && ls -lh "$DEST_ARCHIVE"
}

extract_archive() {
  local archive target
  archive="$(ask_input "Archive path" "${DEST_ARCHIVE:-}")"
  require_not_empty "$archive" "Archive path"
  [[ ! -f "$archive" ]] && { log_error "Archive not found: $archive"; return 1; }

  target="$(ask_input "Extraction target directory" "$(pwd)")"
  require_not_empty "$target" "Target directory"
  if [[ ! -d "$target" ]]; then
    if ask_confirm "Create target directory '$target'?"; then
      run_cmd mkdir -p "$target"
    else
      log_warn "Cancelled."
      return 0
    fi
  fi

  log_warn "Extraction can overwrite files when archive paths already exist."
  if ! ask_confirm "Extract '$archive' into '$target'?"; then
    log_warn "Cancelled."
    return 0
  fi

  case "$archive" in
    *.zip)
      ensure_command_or_offer_install unzip
      run_cmd unzip "$archive" -d "$target"
      ;;
    *.tar.gz|*.tgz)
      ensure_command_or_offer_install tar
      run_cmd tar -xzf "$archive" -C "$target"
      ;;
    *.tar.bz2|*.tbz2)
      ensure_command_or_offer_install tar
      run_cmd tar -xjf "$archive" -C "$target"
      ;;
    *.tar.xz|*.txz)
      ensure_command_or_offer_install tar
      run_cmd tar -xJf "$archive" -C "$target"
      ;;
    *)
      log_error "Unsupported archive extension."
      return 1
      ;;
  esac

  log_ok "Extraction complete: $target"
}

list_archive_contents() {
  local archive
  archive="$(ask_input "Archive path" "${DEST_ARCHIVE:-}")"
  require_not_empty "$archive" "Archive path"
  [[ ! -f "$archive" ]] && { log_error "Archive not found: $archive"; return 1; }

  case "$archive" in
    *.zip)
      ensure_command_or_offer_install unzip
      unzip -l "$archive" | sed -n '1,120p'
      ;;
    *.tar.gz|*.tgz|*.tar.bz2|*.tbz2|*.tar.xz|*.txz)
      ensure_command_or_offer_install tar
      tar -tf "$archive" | sed -n '1,160p'
      ;;
    *)
      log_error "Unsupported archive extension."
      return 1
      ;;
  esac
}

create_checksum() {
  local file algo sum_file
  file="$(ask_input "File to checksum" "${DEST_ARCHIVE:-}")"
  require_not_empty "$file" "File"
  [[ ! -f "$file" ]] && { log_error "File not found: $file"; return 1; }

  menu_select "Checksum Algorithm" "Cancel" \
    "1:sha256" \
    "2:sha512" \
    "3:md5"
  case "$REPLY" in
    1) algo="sha256sum" ;;
    2) algo="sha512sum" ;;
    3) algo="md5sum" ;;
    0) return 0 ;;
    *) log_warn "Invalid option."; return 1 ;;
  esac

  require_command "$algo"
  sum_file="${file}.${algo%sum}"
  if [[ -e "$sum_file" ]] && ! ask_confirm "Overwrite checksum file '$sum_file'?"; then
    log_warn "Cancelled."
    return 0
  fi

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    log_info "[DRY-RUN] Would write checksum file: $sum_file"
  else
    "$algo" "$file" > "$sum_file"
  fi
  log_ok "Checksum written: $sum_file"
}

verify_checksum() {
  local checksum_file
  checksum_file="$(ask_input "Checksum file path")"
  require_not_empty "$checksum_file" "Checksum file"
  [[ ! -f "$checksum_file" ]] && { log_error "File not found: $checksum_file"; return 1; }

  case "$checksum_file" in
    *.sha256) require_command sha256sum; run_cmd sha256sum -c "$checksum_file" ;;
    *.sha512) require_command sha512sum; run_cmd sha512sum -c "$checksum_file" ;;
    *.md5) require_command md5sum; run_cmd md5sum -c "$checksum_file" ;;
    *)
      log_error "Unsupported checksum extension. Expected .sha256, .sha512 or .md5."
      return 1
      ;;
  esac
}

show_status() {
  echo
  log_info "Source     : ${SOURCE_PATH:-<not set>}"
  log_info "Format     : ${ARCHIVE_FORMAT}"
  log_info "Destination: ${DEST_ARCHIVE:-<not set>}"
  if command -v zip >/dev/null 2>&1; then log_ok "zip: $(command -v zip)"; else log_warn "zip: missing"; fi
  if command -v unzip >/dev/null 2>&1; then log_ok "unzip: $(command -v unzip)"; else log_warn "unzip: missing"; fi
  if command -v tar >/dev/null 2>&1; then log_ok "tar: $(command -v tar)"; else log_warn "tar: missing"; fi
  echo
}

# ---------------------------------------------------------------------------
# MENU
# ---------------------------------------------------------------------------
main_menu_choice() {
  menu_select "$SCRIPT_NAME" "Exit" \
    "1:Show disks and filesystem usage" \
    "2:Set source path" \
    "3:Select archive format" \
    "4:Set destination archive" \
    "5:Show current configuration" \
    "6:Create archive" \
    "7:List archive contents" \
    "8:Extract archive" \
    "9:Create checksum" \
    "10:Verify checksum" \
    "11:Install archive tools" \
    "e:Show environment info"
}

main() {
  while true; do
    print_script_header "$SCRIPT_NAME" "$SCRIPT_DESC"
    show_status
    main_menu_choice
    echo

    case "${REPLY:-}" in
      1) show_disks || true; pause ;;
      2) set_source || true; pause ;;
      3) select_format || true; pause ;;
      4) set_destination || true; pause ;;
      5) show_current_config || true; pause ;;
      6) create_archive || true; pause ;;
      7) list_archive_contents || true; pause ;;
      8) extract_archive || true; pause ;;
      9) create_checksum || true; pause ;;
      10) verify_checksum || true; pause ;;
      11) install_archive_tools || true; pause ;;
      e|E) show_env_info; pause ;;
      0) log_info "Bye!"; exit 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

main "$@"
