#!/usr/bin/env bash
# scripts/k8s-tools.sh — Extra Kubernetes CLI tools installer
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
register_cleanup

SCRIPT_NAME="K8s Extra Tools"
SCRIPT_DESC="Install and inspect extra Kubernetes tools"

handle_standard_args "$@"

github_latest_version() {
  local repo="$1" tmp
  tmp="$(make_tmpfile)"
  download_file "https://api.github.com/repos/${repo}/releases/latest" "$tmp"
  grep '"tag_name"' "$tmp" | head -1 | sed 's/.*"v\{0,1\}\([^"]*\)".*/\1/'
}

install_binary_url() {
  local name="$1" url="$2" mode="${3:-plain}"
  local tmpdir
  tmpdir="$(make_tmpdir)"
  check_sudo || return 1
  require_internet
  case "$mode" in
    plain)
      download_file "$url" "${tmpdir}/${name}"
      run_cmd_sudo install -m 0755 "${tmpdir}/${name}" "/usr/local/bin/${name}"
      ;;
    tar.gz)
      download_file "$url" "${tmpdir}/${name}.tar.gz"
      run_cmd tar -xzf "${tmpdir}/${name}.tar.gz" -C "$tmpdir"
      run_cmd_sudo install -m 0755 "${tmpdir}/${name}" "/usr/local/bin/${name}"
      ;;
  esac
}

install_k9s() {
  if [[ "$(detect_package_manager >/dev/null 2>&1; echo "$PKG_MANAGER")" == "brew" ]]; then
    run_cmd brew install k9s
    return
  fi
  local arch version url
  arch="$(get_arch_suffix)"
  version="$(github_latest_version derailed/k9s)"
  url="https://github.com/derailed/k9s/releases/download/v${version}/k9s_Linux_${arch}.tar.gz"
  install_binary_url k9s "$url" tar.gz
}

install_kubectx_kubens() {
  if [[ "$(detect_package_manager >/dev/null 2>&1; echo "$PKG_MANAGER")" == "brew" ]]; then
    run_cmd brew install kubectx
    return
  fi
  check_sudo || return 1
  require_internet
  local tmpdir
  tmpdir="$(make_tmpdir)"
  download_file "https://raw.githubusercontent.com/ahmetb/kubectx/master/kubectx" "${tmpdir}/kubectx"
  download_file "https://raw.githubusercontent.com/ahmetb/kubectx/master/kubens" "${tmpdir}/kubens"
  run_cmd_sudo install -m 0755 "${tmpdir}/kubectx" /usr/local/bin/kubectx
  run_cmd_sudo install -m 0755 "${tmpdir}/kubens" /usr/local/bin/kubens
}

install_stern() {
  if [[ "$(detect_package_manager >/dev/null 2>&1; echo "$PKG_MANAGER")" == "brew" ]]; then
    run_cmd brew install stern
    return
  fi
  local arch version url
  arch="$(get_arch_suffix)"
  version="$(github_latest_version stern/stern)"
  url="https://github.com/stern/stern/releases/download/v${version}/stern_${version}_linux_${arch}.tar.gz"
  install_binary_url stern "$url" tar.gz
}

install_kustomize() {
  if [[ "$(detect_package_manager >/dev/null 2>&1; echo "$PKG_MANAGER")" == "brew" ]]; then
    run_cmd brew install kustomize
    return
  fi
  check_sudo || return 1
  require_internet
  local tmpdir
  tmpdir="$(make_tmpdir)"
  download_file "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" "${tmpdir}/install_kustomize.sh"
  run_cmd bash "${tmpdir}/install_kustomize.sh" "$tmpdir"
  run_cmd_sudo install -m 0755 "${tmpdir}/kustomize" /usr/local/bin/kustomize
}

install_kind() {
  if [[ "$(detect_package_manager >/dev/null 2>&1; echo "$PKG_MANAGER")" == "brew" ]]; then
    run_cmd brew install kind
    return
  fi
  local arch version url
  arch="$(get_arch_suffix)"
  version="$(github_latest_version kubernetes-sigs/kind)"
  url="https://kind.sigs.k8s.io/dl/v${version}/kind-linux-${arch}"
  install_binary_url kind "$url" plain
}

install_all() {
  install_k9s || true
  install_kubectx_kubens || true
  install_stern || true
  install_kustomize || true
  install_kind || true
}

show_tool_status() {
  local -a tools=(kubectl helm k9s kubectx kubens stern kustomize kind)
  local tool
  for tool in "${tools[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
      log_ok "$tool: $(command -v "$tool")"
      "$tool" version 2>/dev/null | head -3 || "$tool" --version 2>/dev/null | head -3 || true
    else
      log_warn "$tool: missing"
    fi
    echo
  done
}

main_menu_choice() {
  menu_select "$SCRIPT_NAME" "Exit" \
    "1:Show tool status" \
    "2:Install k9s" \
    "3:Install kubectx/kubens" \
    "4:Install stern" \
    "5:Install kustomize" \
    "6:Install kind" \
    "7:Install all listed tools" \
    "e:Show environment info"
}

main() {
  while true; do
    print_script_header "$SCRIPT_NAME" "$SCRIPT_DESC"
    main_menu_choice
    echo
    case "${REPLY:-}" in
      1) show_tool_status || true; pause ;;
      2) install_k9s || true; pause ;;
      3) install_kubectx_kubens || true; pause ;;
      4) install_stern || true; pause ;;
      5) install_kustomize || true; pause ;;
      6) install_kind || true; pause ;;
      7) install_all || true; pause ;;
      e|E) show_env_info; pause ;;
      0) log_info "Bye!"; exit 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

main "$@"
