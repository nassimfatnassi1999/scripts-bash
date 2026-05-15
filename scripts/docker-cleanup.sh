#!/usr/bin/env bash
# scripts/docker-cleanup.sh — Docker Cleanup, Audit & Management
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
register_cleanup

SCRIPT_NAME="Docker Cleanup & Audit"
SCRIPT_DESC="Inspect, clean and manage Docker resources"

handle_standard_args "$@"

# ---------------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------------
docker_ok() {
  if ! is_installed docker; then
    log_error "docker not found. Install Docker first."
    return 1
  fi
  if ! docker info >/dev/null 2>&1; then
    log_error "Cannot communicate with Docker daemon."
    log_info "Fix: sudo systemctl start docker"
    log_info "     sudo usermod -aG docker \$USER && newgrp docker"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# AUDIT / INFO
# ---------------------------------------------------------------------------
docker_status() {
  docker_ok || return 1
  log_info "Docker version:"
  docker version
  echo
  log_info "Docker info (summary):"
  docker info 2>/dev/null | head -30
}

disk_usage() {
  docker_ok || return 1
  docker system df -v
}

list_containers() {
  docker_ok || return 1
  log_info "Running containers:"
  docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
  echo
  log_info "All containers:"
  docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.CreatedAt}}'
}

containers_in_trouble() {
  docker_ok || return 1
  log_info "Exited containers:"
  docker ps -a --filter status=exited --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
  echo
  log_info "Restarting containers:"
  docker ps -a --filter status=restarting --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
  echo
  log_info "Unhealthy containers:"
  docker ps -a --filter health=unhealthy --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
  echo
  log_info "Typical causes and fixes:"
  echo "  - App crash       : check logs (option 12), fix config/env/ports"
  echo "  - DB unreachable  : check network/compose startup order"
  echo "  - OOMKilled       : add memory limit or optimize app"
  echo "  - Healthcheck fail: verify endpoint and service readiness"
}

images_by_size() {
  docker_ok || return 1
  log_info "Images sorted by size (ascending):"
  docker images --format '{{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Size}}' | sort -h -k3
  echo
  log_info "Tip: Use multi-stage builds and clean apt cache to reduce image size."
}

dangling_images() {
  docker_ok || return 1
  log_info "Dangling (unused) images:"
  docker images -f dangling=true
}

# ---------------------------------------------------------------------------
# CLEANUP OPERATIONS
# ---------------------------------------------------------------------------
cleanup_safe() {
  docker_ok || return 1
  log_warn "SAFE cleanup will remove:"
  echo "  - Stopped containers"
  echo "  - Dangling images"
  echo
  if ! ask_confirm "Proceed with SAFE cleanup?"; then log_warn "Cancelled."; return 0; fi
  docker container prune -f
  docker image prune -f
  log_ok "SAFE cleanup done."
}

cleanup_normal() {
  docker_ok || return 1
  log_warn "NORMAL cleanup (docker system prune) will remove:"
  echo "  - Stopped containers"
  echo "  - Unused networks"
  echo "  - Dangling images"
  echo "  Volumes are KEPT."
  echo
  if ! ask_confirm "Proceed with NORMAL cleanup?"; then log_warn "Cancelled."; return 0; fi
  docker system prune -f
  log_ok "NORMAL cleanup done."
}

cleanup_aggressive() {
  docker_ok || return 1
  log_warn "AGGRESSIVE cleanup will remove EVERYTHING unused including VOLUMES."
  log_warn "This can delete database data if you store it in Docker volumes!"
  echo
  if ! ask_confirm "First confirmation: proceed?"; then log_warn "Cancelled."; return 0; fi
  if ! ask_confirm "Second confirmation: DELETE VOLUMES TOO?"; then log_warn "Cancelled."; return 0; fi
  docker system prune -a --volumes -f
  log_ok "AGGRESSIVE cleanup done."
}

remove_container() {
  docker_ok || return 1
  list_containers || true
  echo
  local c
  c="$(ask_input "Container name or ID to remove")"
  require_not_empty "$c" "Container name"
  if ! ask_confirm "Force-remove container '$c'?"; then log_warn "Cancelled."; return 0; fi
  docker rm -f "$c"
  log_ok "Container removed: $c"
}

remove_image() {
  docker_ok || return 1
  docker images | head -20
  echo
  local img
  img="$(ask_input "Image name:tag or ID to remove")"
  require_not_empty "$img" "Image"
  if ! ask_confirm "Force-remove image '$img'?"; then log_warn "Cancelled."; return 0; fi
  docker rmi -f "$img"
  log_ok "Image removed: $img"
}

stop_container() {
  docker_ok || return 1
  docker ps --format 'table {{.Names}}\t{{.Status}}'
  echo
  local c
  c="$(ask_input "Container name or ID to stop")"
  require_not_empty "$c" "Container name"
  docker stop "$c"
  log_ok "Container stopped: $c"
}

start_container() {
  docker_ok || return 1
  docker ps -a --format 'table {{.Names}}\t{{.Status}}' | grep -v "Up " || true
  echo
  local c
  c="$(ask_input "Container name or ID to start")"
  require_not_empty "$c" "Container name"
  docker start "$c"
  log_ok "Container started: $c"
}

# ---------------------------------------------------------------------------
# LOGS
# ---------------------------------------------------------------------------
view_logs() {
  docker_ok || return 1
  docker ps --format '{{.Names}}'
  echo
  local c
  c="$(ask_input "Container name/ID")"
  require_not_empty "$c" "Container name"
  local lines
  lines="$(ask_input "Number of lines" "200")"
  local follow
  if ask_confirm "Follow logs live? (Ctrl+C to stop)"; then
    log_info "Press Ctrl+C to stop following."
    docker logs -n "$lines" -f "$c"
  else
    docker logs -n "$lines" "$c"
  fi
}

# ---------------------------------------------------------------------------
# IMPORT / EXPORT
# ---------------------------------------------------------------------------
export_container() {
  docker_ok || return 1
  local c; c="$(ask_input "Container name/ID to export")"
  require_not_empty "$c" "Container name"
  local tarpath; tarpath="$(ask_input "Destination tar path" "/tmp/${c}-container.tar")"
  require_not_empty "$tarpath" "Tar path"
  if [[ -e "$tarpath" ]]; then
    if ! ask_confirm "File exists. Overwrite?"; then log_warn "Cancelled."; return 0; fi
    rm -f "$tarpath"
  fi
  docker export -o "$tarpath" "$c"
  log_ok "Container exported to: $tarpath ($(du -h "$tarpath" | cut -f1))"
}

save_image() {
  docker_ok || return 1
  docker images | head -20
  echo
  local img; img="$(ask_input "Image name:tag or ID to save")"
  require_not_empty "$img" "Image"
  local tarpath; tarpath="$(ask_input "Destination tar path" "/tmp/image.tar")"
  require_not_empty "$tarpath" "Tar path"
  if [[ -e "$tarpath" ]]; then
    if ! ask_confirm "File exists. Overwrite?"; then log_warn "Cancelled."; return 0; fi
    rm -f "$tarpath"
  fi
  docker save -o "$tarpath" "$img"
  log_ok "Image saved to: $tarpath ($(du -h "$tarpath" | cut -f1))"
}

load_image() {
  docker_ok || return 1
  local tarpath; tarpath="$(ask_input "Path to image tar file")"
  require_not_empty "$tarpath" "Tar path"
  [[ ! -f "$tarpath" ]] && { log_error "File not found: $tarpath"; return 1; }
  docker load -i "$tarpath"
  log_ok "Image loaded from: $tarpath"
}

# ---------------------------------------------------------------------------
# NETWORK & VOLUME INFO
# ---------------------------------------------------------------------------
list_networks() {
  docker_ok || return 1
  log_info "Docker networks:"
  docker network ls
  echo
  log_info "Network details:"
  docker network inspect bridge 2>/dev/null | head -30 || true
}

list_volumes() {
  docker_ok || return 1
  log_info "Docker volumes:"
  docker volume ls
  echo
  log_info "Unused volumes:"
  docker volume ls -f dangling=true
}

# ---------------------------------------------------------------------------
# MENU
# ---------------------------------------------------------------------------
main() {
  while true; do
    print_script_header "$SCRIPT_NAME" "$SCRIPT_DESC"

    if is_installed docker && docker info >/dev/null 2>&1; then
      log_ok "Docker daemon: running"
    else
      log_warn "Docker daemon: NOT running or not installed"
    fi
    echo

    echo "  ${BOLD}${YELLOW}Audit / Info${RESET}"
    echo "  ${CYAN}1)${RESET}  Docker status & version"
    echo "  ${CYAN}2)${RESET}  Disk usage (docker system df)"
    echo "  ${CYAN}3)${RESET}  List all containers"
    echo "  ${CYAN}4)${RESET}  Containers with problems (exited/restarting/unhealthy)"
    echo "  ${CYAN}5)${RESET}  Images sorted by size"
    echo "  ${CYAN}6)${RESET}  Dangling (unused) images"
    echo "  ${CYAN}7)${RESET}  List networks"
    echo "  ${CYAN}8)${RESET}  List volumes"
    print_menu_separator
    echo "  ${BOLD}${YELLOW}Cleanup${RESET}"
    echo "  ${CYAN}9)${RESET}  Cleanup SAFE   (stopped containers + dangling images)"
    echo "  ${CYAN}10)${RESET} Cleanup NORMAL (docker system prune, keeps volumes)"
    echo "  ${CYAN}11)${RESET} Cleanup AGGRESSIVE (prune -a --volumes — DELETES DATA)"
    print_menu_separator
    echo "  ${BOLD}${YELLOW}Container Management${RESET}"
    echo "  ${CYAN}12)${RESET} Remove specific container"
    echo "  ${CYAN}13)${RESET} Stop container"
    echo "  ${CYAN}14)${RESET} Start container"
    echo "  ${CYAN}15)${RESET} Remove specific image"
    echo "  ${CYAN}16)${RESET} View container logs"
    print_menu_separator
    echo "  ${BOLD}${YELLOW}Import / Export${RESET}"
    echo "  ${CYAN}17)${RESET} Export container to tar"
    echo "  ${CYAN}18)${RESET} Save image to tar"
    echo "  ${CYAN}19)${RESET} Load image from tar"
    print_menu_separator
    echo "  ${CYAN}e)${RESET}  Show environment info"
    echo "  ${CYAN}0)${RESET}  Exit"
    echo
    read -r -p "Choose: " c
    echo
    case "${c:-}" in
      1)  docker_status || true; pause ;;
      2)  disk_usage || true; pause ;;
      3)  list_containers || true; pause ;;
      4)  containers_in_trouble || true; pause ;;
      5)  images_by_size || true; pause ;;
      6)  dangling_images || true; pause ;;
      7)  list_networks || true; pause ;;
      8)  list_volumes || true; pause ;;
      9)  cleanup_safe || true; pause ;;
      10) cleanup_normal || true; pause ;;
      11) cleanup_aggressive || true; pause ;;
      12) remove_container || true; pause ;;
      13) stop_container || true; pause ;;
      14) start_container || true; pause ;;
      15) remove_image || true; pause ;;
      16) view_logs || true; pause ;;
      17) export_container || true; pause ;;
      18) save_image || true; pause ;;
      19) load_image || true; pause ;;
      e|E) show_env_info; pause ;;
      0) log_info "Bye!"; exit 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

main "$@"
