#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# =====================================
# Docker Toolbox: Cleanup + Audit (Menu)
# =====================================

# ---- Colors ----
if command -v tput >/dev/null 2>&1; then
  BOLD="$(tput bold)"; RESET="$(tput sgr0)"
  RED="$(tput setaf 1)"; GREEN="$(tput setaf 2)"; YELLOW="$(tput setaf 3)"
  CYAN="$(tput setaf 6)"; MAGENTA="$(tput setaf 5)"
else
  BOLD=""; RESET=""; RED=""; GREEN=""; YELLOW=""; CYAN=""; MAGENTA=""
fi

ok()   { echo "${GREEN}${BOLD}[OK]${RESET} $*"; }
info() { echo "${CYAN}${BOLD}[i]${RESET} $*"; }
warn() { echo "${YELLOW}${BOLD}[!]${RESET} $*"; }
err()  { echo "${RED}${BOLD}[X]${RESET} $*" >&2; }
pause(){ read -r -p "Press Enter to continue... " _; }

need_cmd(){ command -v "$1" >/dev/null 2>&1; }

docker_ok() {
  if ! need_cmd docker; then
    err "docker not found. Install Docker first."
    return 1
  fi
  if ! docker info >/dev/null 2>&1; then
    err "Cannot talk to Docker daemon."
    echo "Fix ideas:"
    echo "  - sudo systemctl status docker"
    echo "  - sudo systemctl start docker"
    echo "  - Add your user to docker group: sudo usermod -aG docker \$USER && newgrp docker"
    echo "  - Or run this script with sudo"
    return 1
  fi
}

confirm() {
  local p="${1:-Are you sure? (y/N): }"
  local a
  read -r -p "$p" a
  [[ "${a:-}" == "y" || "${a:-}" == "Y" ]]
}

header() {
  clear || true
  echo "${BOLD}${MAGENTA}========================================${RESET}"
  echo "${BOLD}${MAGENTA}     Docker Toolbox (Audit + Cleanup)   ${RESET}"
  echo "${BOLD}${MAGENTA}========================================${RESET}"
  echo "Host: $(hostname) | Date: $(date +'%F %T')"
  echo
}

menu() {
  echo "${BOLD}1) Docker status (info + versions)${RESET}"
  echo "${BOLD}2) Disk usage summary (docker system df)${RESET}"
  echo "${BOLD}3) List containers (running + all)${RESET}"
  echo "${BOLD}4) Show containers in trouble (exited/restarting/unhealthy)${RESET}"
  echo "${BOLD}5) List images (sorted by size)${RESET}"
  echo "${BOLD}6) List dangling (unused) images${RESET}"
  echo "${BOLD}7) Cleanup SAFE: remove stopped containers + dangling images${RESET}"
  echo "${BOLD}8) Cleanup NORMAL: docker system prune (keeps volumes)${RESET}"
  echo "${BOLD}9) Cleanup AGGRESSIVE: docker system prune -a --volumes${RESET}"
  echo "${BOLD}10) Remove specific container${RESET}"
  echo "${BOLD}11) Remove specific image${RESET}"
  echo "${BOLD}12) View logs of a container (tail/follow)${RESET}"
  echo "${BOLD}13) Export container to tar${RESET}"
  echo "${BOLD}14) Save image to tar${RESET}"
  echo "${BOLD}15) Load image from tar${RESET}"
  echo "${BOLD}0) Exit${RESET}"
  echo
}

docker_status() {
  docker_ok
  info "Docker version:"
  docker version || true
  echo
  info "Docker info (short):"
  docker info 2>/dev/null | sed -n '1,80p' || true
  echo
  info "Docker root dir:"
  docker info --format '{{.DockerRootDir}}' 2>/dev/null || true
}

disk_usage() {
  docker_ok
  docker system df -v
}

list_containers() {
  docker_ok
  info "Running containers:"
  docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' || true
  echo
  info "All containers:"
  docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' || true
}

containers_in_trouble() {
  docker_ok
  info "Exited containers:"
  docker ps -a --filter status=exited --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' || true
  echo
  info "Restarting containers:"
  docker ps -a --filter status=restarting --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' || true
  echo
  info "Unhealthy containers (if HEALTHCHECK exists):"
  docker ps -a --filter health=unhealthy --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' || true

  echo
  echo "Typical causes + fixes:"
  echo "  - App crash: check logs (menu 12), fix config/env vars/ports"
  echo "  - Missing dependency (DB not reachable): check network/compose order"
  echo "  - OOMKilled: add memory or optimize; check: docker inspect <container>"
  echo "  - Healthcheck failing: verify endpoint/command and service readiness"
}

images_sorted_by_size() {
  docker_ok
  info "Images sorted by size (DESC):"
  # docker images doesn't sort by size reliably; use --format + sort
  docker images --format '{{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Size}}' \
    | awk '{print $0}' \
    | sort -h -k3
  echo
  echo "Tip: huge images => check multi-stage builds, clean apt cache, remove build deps."
}

dangling_images() {
  docker_ok
  info "Dangling images:"
  docker images -f dangling=true
}

cleanup_safe() {
  docker_ok
  warn "SAFE cleanup will remove:"
  echo "  - stopped containers"
  echo "  - dangling images"
  echo
  if ! confirm "Proceed? (y/N): "; then warn "Cancelled."; return 0; fi

  docker container prune -f
  docker image prune -f
  ok "SAFE cleanup done."
}

cleanup_normal() {
  docker_ok
  warn "NORMAL cleanup = docker system prune"
  echo "Removes:"
  echo "  - stopped containers"
  echo "  - unused networks"
  echo "  - dangling images"
  echo "Keeps volumes."
  echo
  if ! confirm "Proceed? (y/N): "; then warn "Cancelled."; return 0; fi

  docker system prune -f
  ok "NORMAL cleanup done."
}

cleanup_aggressive() {
  docker_ok
  warn "AGGRESSIVE cleanup = docker system prune -a --volumes"
  echo "Removes almost everything unused, INCLUDING VOLUMES."
  echo "This can delete databases/data if you rely on volumes."
  echo
  if ! confirm "Proceed? (y/N): "; then warn "Cancelled."; return 0; fi
  if ! confirm "Second confirmation: delete UNUSED volumes too? (y/N): "; then warn "Cancelled."; return 0; fi

  docker system prune -a --volumes -f
  ok "AGGRESSIVE cleanup done."
}

remove_container() {
  docker_ok
  read -r -p "Container name or ID to remove (example: myapp): " c
  [[ -z "${c:-}" ]] && { err "Empty input."; return 1; }
  docker ps -a --format 'table {{.Names}}\t{{.ID}}\t{{.Status}}' | sed -n '1,30p' || true
  echo
  if ! confirm "Remove container '$c'? (y/N): "; then warn "Cancelled."; return 0; fi
  docker rm -f "$c"
  ok "Container removed: $c"
}

remove_image() {
  docker_ok
  read -r -p "Image name:tag or ID to remove (example: nginx:latest): " img
  [[ -z "${img:-}" ]] && { err "Empty input."; return 1; }
  docker images | sed -n '1,30p' || true
  echo
  if ! confirm "Remove image '$img'? (y/N): "; then warn "Cancelled."; return 0; fi
  docker rmi -f "$img"
  ok "Image removed: $img"
}

view_logs() {
  docker_ok
  read -r -p "Container name/ID (example: myapp): " c
  [[ -z "${c:-}" ]] && { err "Empty input."; return 1; }
  local lines follow
  read -r -p "How many lines? (default 200): " lines
  lines="${lines:-200}"
  read -r -p "Follow logs live? (y/N): " follow
  if [[ "${follow,,}" == "y" ]]; then
    info "Press Ctrl+C to stop following."
    docker logs -n "$lines" -f "$c"
  else
    docker logs -n "$lines" "$c"
  fi
}

export_container() {
  docker_ok
  read -r -p "Container name/ID to export (example: myapp): " c
  [[ -z "${c:-}" ]] && { err "Empty input."; return 1; }
  read -r -p "Destination tar path (example: /tmp/myapp-container.tar): " tarpath
  [[ -z "${tarpath:-}" ]] && { err "Empty tar path."; return 1; }
  if [[ -e "$tarpath" ]]; then
    warn "File exists: $tarpath"
    confirm "Overwrite? (y/N): " || { warn "Cancelled."; return 0; }
    rm -f "$tarpath"
  fi
  docker export -o "$tarpath" "$c"
  ok "Container exported to: $tarpath"
}

save_image() {
  docker_ok
  read -r -p "Image (name:tag or ID) to save (example: nginx:latest): " img
  [[ -z "${img:-}" ]] && { err "Empty image."; return 1; }
  read -r -p "Destination tar path (example: /tmp/nginx-image.tar): " tarpath
  [[ -z "${tarpath:-}" ]] && { err "Empty tar path."; return 1; }
  if [[ -e "$tarpath" ]]; then
    warn "File exists: $tarpath"
    confirm "Overwrite? (y/N): " || { warn "Cancelled."; return 0; }
    rm -f "$tarpath"
  fi
  docker save -o "$tarpath" "$img"
  ok "Image saved to: $tarpath"
}

load_image() {
  docker_ok
  read -r -p "Path to image tar file (example: /tmp/nginx-image.tar): " tarpath
  [[ -z "${tarpath:-}" ]] && { err "Empty path."; return 1; }
  if [[ ! -f "$tarpath" ]]; then err "File not found: $tarpath"; return 1; fi
  docker load -i "$tarpath"
  ok "Image loaded from: $tarpath"
}

main() {
  while true; do
    header
    menu
    read -r -p "Choose an option: " c
    echo
    case "${c:-}" in
      1) docker_status; pause ;;
      2) disk_usage; pause ;;
      3) list_containers; pause ;;
      4) containers_in_trouble; pause ;;
      5) images_sorted_by_size; pause ;;
      6) dangling_images; pause ;;
      7) cleanup_safe; pause ;;
      8) cleanup_normal; pause ;;
      9) cleanup_aggressive; pause ;;
      10) remove_container; pause ;;
      11) remove_image; pause ;;
      12) view_logs; pause ;;
      13) export_container; pause ;;
      14) save_image; pause ;;
      15) load_image; pause ;;
      0) info "Bye."; exit 0 ;;
      *) warn "Invalid option."; pause ;;
    esac
  done
}

main