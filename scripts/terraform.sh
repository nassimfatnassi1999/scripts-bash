#!/usr/bin/env bash
# scripts/terraform.sh — Terraform / OpenTofu installer and workflow manager
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"
register_cleanup

SCRIPT_NAME="Terraform Manager"
SCRIPT_DESC="Install Terraform/OpenTofu and run init/plan/apply/destroy workflows"

handle_standard_args "$@"

TF_CMD="${TF_CMD:-}"

# ---------------------------------------------------------------------------
# UI HELPERS
# ---------------------------------------------------------------------------
write_sudo_file() {
  local dest="$1"
  local content="$2"

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    log_info "[DRY-RUN] Would write sudo file: $dest"
    return 0
  fi

  printf '%s\n' "$content" | sudo tee "$dest" >/dev/null
}

install_packages_if_missing() {
  local -a packages=("$@")
  local pkg
  detect_package_manager
  for pkg in "${packages[@]}"; do
    case "$PKG_MANAGER" in
      apt)
        dpkg -s "$pkg" >/dev/null 2>&1 || install_package "$pkg"
        ;;
      dnf|yum|zypper)
        rpm -q "$pkg" >/dev/null 2>&1 || install_package "$pkg"
        ;;
      pacman)
        pacman -Q "$pkg" >/dev/null 2>&1 || install_package "$pkg"
        ;;
      apk)
        apk info -e "$pkg" >/dev/null 2>&1 || install_package "$pkg"
        ;;
      *)
        log_warn "Cannot verify package '$pkg': unsupported package manager."
        ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# DETECTION / STATUS
# ---------------------------------------------------------------------------
detect_tf_cmd() {
  if [[ -n "$TF_CMD" ]] && command -v "$TF_CMD" >/dev/null 2>&1; then
    return 0
  fi

  if is_installed terraform; then
    TF_CMD="terraform"
  elif is_installed tofu; then
    TF_CMD="tofu"
  else
    TF_CMD=""
  fi
}

tool_version_line() {
  local cmd="$1"
  "$cmd" version 2>/dev/null | head -1 || true
}

show_tf_status() {
  detect_tf_cmd
  echo
  log_info "=== Terraform / OpenTofu Status ==="
  if is_installed terraform; then
    log_ok "Terraform: $(tool_version_line terraform)"
  else
    log_warn "Terraform: NOT installed"
  fi

  if is_installed tofu; then
    log_ok "OpenTofu: $(tool_version_line tofu)"
  else
    log_warn "OpenTofu: NOT installed"
  fi

  if [[ -n "$TF_CMD" ]]; then
    log_info "Selected tool: $TF_CMD"
  else
    log_warn "Selected tool: none"
  fi

  echo
  log_info "Working directory: $(pwd)"
  if compgen -G "*.tf" >/dev/null; then
    ls ./*.tf 2>/dev/null | sed 's#^\./#  - #'
  else
    log_warn "No .tf files found in current directory."
  fi
  echo
}

select_tf_cmd() {
  local -a items=()
  is_installed terraform && items+=("1:Terraform")
  is_installed tofu && items+=("2:OpenTofu")

  if [[ "${#items[@]}" -eq 0 ]]; then
    log_error "No Terraform or OpenTofu binary found."
    return 1
  fi

  menu_select "Select IaC Tool" "Cancel" "${items[@]}"
  case "$REPLY" in
    1) TF_CMD="terraform"; log_ok "Selected Terraform." ;;
    2) TF_CMD="tofu"; log_ok "Selected OpenTofu." ;;
    0) return 0 ;;
    *) log_warn "Invalid option." ;;
  esac
}

# ---------------------------------------------------------------------------
# INSTALL TERRAFORM
# ---------------------------------------------------------------------------
install_terraform() {
  if is_installed terraform; then
    log_ok "Terraform already installed: $(tool_version_line terraform)"
    if ! ask_confirm "Reinstall / update Terraform?"; then return 0; fi
  fi

  require_internet
  check_sudo
  detect_package_manager

  case "$PKG_MANAGER" in
    apt) _install_terraform_apt ;;
    dnf|yum) _install_terraform_rpm ;;
    pacman) _install_terraform_pacman ;;
    zypper) _install_terraform_zypper ;;
    apk) _install_terraform_binary ;;
    *) _install_terraform_binary ;;
  esac

  if is_installed terraform || [[ "${DRY_RUN:-0}" == "1" ]]; then
    TF_CMD="terraform"
    log_ok "Terraform installation step completed."
    is_installed terraform && log_ok "$(tool_version_line terraform)"
  fi
}

_install_terraform_apt() {
  log_step "Installing Terraform via HashiCorp apt repository..."
  install_packages_if_missing ca-certificates curl gnupg lsb-release
  run_cmd_sudo install -d -m 0755 /usr/share/keyrings

  local tmpdir
  tmpdir="$(make_tmpdir)"
  download_file "https://apt.releases.hashicorp.com/gpg" "${tmpdir}/hashicorp.asc"
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    log_info "[DRY-RUN] Would install HashiCorp apt key."
  else
    gpg --dearmor < "${tmpdir}/hashicorp.asc" | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg >/dev/null
  fi

  local codename arch
  if command -v lsb_release >/dev/null 2>&1; then
    codename="$(lsb_release -cs)"
  else
    # shellcheck disable=SC1091
    . /etc/os-release
    codename="${VERSION_CODENAME:-bookworm}"
  fi
  arch="$(dpkg --print-architecture 2>/dev/null || echo "amd64")"
  write_sudo_file /etc/apt/sources.list.d/hashicorp.list \
    "deb [arch=${arch} signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com ${codename} main"
  run_cmd_sudo apt-get update -y
  run_cmd_sudo apt-get install -y terraform
}

_install_terraform_rpm() {
  log_step "Installing Terraform via HashiCorp rpm repository..."
  install_packages_if_missing dnf-plugins-core || true

  local repo_base="https://rpm.releases.hashicorp.com/RHEL/\$releasever/\$basearch/stable"
  if [[ "${OS_ID:-}" == "fedora" ]]; then
    repo_base="https://rpm.releases.hashicorp.com/fedora/\$releasever/\$basearch/stable"
  fi

  write_sudo_file /etc/yum.repos.d/hashicorp.repo "[hashicorp]
name=HashiCorp Stable - \$basearch
baseurl=${repo_base}
enabled=1
gpgcheck=1
gpgkey=https://rpm.releases.hashicorp.com/gpg"

  # shellcheck disable=SC2086
  run_cmd sudo $PKG_INSTALL terraform
}

_install_terraform_pacman() {
  log_step "Installing Terraform via pacman..."
  run_cmd_sudo pacman -S --noconfirm terraform
}

_install_terraform_zypper() {
  log_step "Trying Terraform via zypper..."
  if ! run_cmd_sudo zypper install -y terraform; then
    log_warn "Terraform package unavailable via zypper. Falling back to binary install."
    _install_terraform_binary
  fi
}

_latest_hashicorp_version() {
  local product="$1"
  local tmp
  tmp="$(make_tmpfile)"

  if download_file "https://api.releases.hashicorp.com/v1/releases/${product}/latest" "$tmp"; then
    grep -o '"version":"[^"]*"' "$tmp" | head -1 | cut -d'"' -f4
  else
    return 1
  fi
}

_install_terraform_binary() {
  log_step "Installing Terraform via binary download..."
  install_packages_if_missing unzip ca-certificates || true
  require_command unzip "Install unzip first."

  local arch version tmpdir url
  arch="$(get_arch_suffix)"
  version="$(_latest_hashicorp_version terraform || true)"
  if [[ -z "$version" ]]; then
    version="$(ask_input "Terraform version" "1.8.5")"
  fi
  require_not_empty "$version" "Terraform version"

  tmpdir="$(make_tmpdir)"
  url="https://releases.hashicorp.com/terraform/${version}/terraform_${version}_linux_${arch}.zip"
  download_file "$url" "${tmpdir}/terraform.zip"
  run_cmd unzip -q "${tmpdir}/terraform.zip" -d "${tmpdir}"
  run_cmd_sudo install -m 0755 "${tmpdir}/terraform" /usr/local/bin/terraform
}

# ---------------------------------------------------------------------------
# INSTALL OPENTOFU
# ---------------------------------------------------------------------------
install_opentofu() {
  if is_installed tofu; then
    log_ok "OpenTofu already installed: $(tool_version_line tofu)"
    if ! ask_confirm "Reinstall / update OpenTofu?"; then return 0; fi
  fi

  require_internet
  check_sudo
  detect_package_manager

  case "$PKG_MANAGER" in
    apt) _install_tofu_apt ;;
    dnf|yum|zypper) _install_tofu_rpm ;;
    pacman) _install_tofu_pacman ;;
    apk) _install_tofu_binary ;;
    *) _install_tofu_binary ;;
  esac

  if is_installed tofu || [[ "${DRY_RUN:-0}" == "1" ]]; then
    TF_CMD="tofu"
    log_ok "OpenTofu installation step completed."
    is_installed tofu && log_ok "$(tool_version_line tofu)"
  fi
}

_install_tofu_apt() {
  log_step "Installing OpenTofu via official apt repository..."
  install_packages_if_missing ca-certificates curl gnupg
  run_cmd_sudo install -d -m 0755 /etc/apt/keyrings /usr/share/keyrings

  local tmpdir
  tmpdir="$(make_tmpdir)"
  download_file "https://get.opentofu.org/opentofu.gpg" "${tmpdir}/opentofu.asc"
  download_file "https://packages.opentofu.org/opentofu/tofu/gpgkey" "${tmpdir}/opentofu-package.asc"

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    log_info "[DRY-RUN] Would install OpenTofu apt keys."
  else
    gpg --dearmor < "${tmpdir}/opentofu.asc" | sudo tee /etc/apt/keyrings/opentofu.gpg >/dev/null
    gpg --dearmor < "${tmpdir}/opentofu-package.asc" | sudo tee /usr/share/keyrings/opentofu-archive-keyring.gpg >/dev/null
  fi

  write_sudo_file /etc/apt/sources.list.d/opentofu.list \
    "deb [signed-by=/etc/apt/keyrings/opentofu.gpg,/usr/share/keyrings/opentofu-archive-keyring.gpg] https://packages.opentofu.org/opentofu/tofu/any/ any main"
  run_cmd_sudo apt-get update -y
  run_cmd_sudo apt-get install -y tofu
}

_install_tofu_rpm() {
  log_step "Installing OpenTofu via official rpm repository..."
  write_sudo_file /etc/yum.repos.d/opentofu.repo '[opentofu]
name=OpenTofu
baseurl=https://packages.opentofu.org/opentofu/tofu/rpm_any/rpm_any/$basearch
repo_gpgcheck=0
gpgcheck=1
enabled=1
gpgkey=https://get.opentofu.org/opentofu.gpg
       https://packages.opentofu.org/opentofu/tofu/gpgkey
sslverify=1
metadata_expire=300'

  # shellcheck disable=SC2086
  run_cmd sudo $PKG_INSTALL tofu
}

_install_tofu_pacman() {
  log_step "Installing OpenTofu on Arch Linux..."
  if pacman -Si opentofu >/dev/null 2>&1; then
    run_cmd_sudo pacman -S --noconfirm opentofu
  elif pacman -Si tofu >/dev/null 2>&1; then
    run_cmd_sudo pacman -S --noconfirm tofu
  else
    log_warn "OpenTofu package unavailable via pacman. Falling back to binary install."
    _install_tofu_binary
  fi
}

_latest_github_version() {
  local repo="$1"
  local tmp
  tmp="$(make_tmpfile)"

  if download_file "https://api.github.com/repos/${repo}/releases/latest" "$tmp"; then
    grep '"tag_name"' "$tmp" | head -1 | sed 's/.*"v\{0,1\}\([^"]*\)".*/\1/'
  else
    return 1
  fi
}

_install_tofu_binary() {
  log_step "Installing OpenTofu via binary download..."
  install_packages_if_missing unzip ca-certificates || true
  require_command unzip "Install unzip first."

  local arch version tmpdir url
  arch="$(get_arch_suffix)"
  version="$(_latest_github_version opentofu/opentofu || true)"
  if [[ -z "$version" ]]; then
    version="$(ask_input "OpenTofu version" "1.8.2")"
  fi
  require_not_empty "$version" "OpenTofu version"

  tmpdir="$(make_tmpdir)"
  url="https://github.com/opentofu/opentofu/releases/download/v${version}/tofu_${version}_linux_${arch}.zip"
  download_file "$url" "${tmpdir}/tofu.zip"
  run_cmd unzip -q "${tmpdir}/tofu.zip" -d "${tmpdir}"
  run_cmd_sudo install -m 0755 "${tmpdir}/tofu" /usr/local/bin/tofu
}

# ---------------------------------------------------------------------------
# WORKFLOW HELPERS
# ---------------------------------------------------------------------------
ensure_tf() {
  detect_tf_cmd
  if [[ -z "$TF_CMD" ]]; then
    log_error "No Terraform or OpenTofu found. Install one first."
    return 1
  fi
}

select_workdir() {
  local tf_dir
  tf_dir="$(ask_input "Terraform working directory" "$(pwd)")"
  require_not_empty "$tf_dir" "Terraform working directory"
  [[ ! -d "$tf_dir" ]] && { log_error "Directory not found: $tf_dir"; return 1; }
  cd "$tf_dir"
  log_info "Working in: $(pwd)"
}

ensure_tf_dir() {
  ensure_tf || return 1
  select_workdir || return 1
}

collect_common_args() {
  local args=""
  local var_file vars lock_timeout

  var_file="$(ask_input "Variable file (leave empty for none)" "")"
  if [[ -n "$var_file" ]]; then
    [[ ! -f "$var_file" ]] && { log_error "Variable file not found: $var_file"; return 1; }
    args="${args} -var-file=${var_file}"
  fi

  vars="$(ask_input "Extra -var entries, comma-separated key=value (leave empty for none)" "")"
  if [[ -n "$vars" ]]; then
    local old_ifs="$IFS"
    local var
    IFS=","
    for var in $vars; do
      var="${var#"${var%%[![:space:]]*}"}"
      var="${var%"${var##*[![:space:]]}"}"
      [[ -n "$var" ]] && args="${args} -var=${var}"
    done
    IFS="$old_ifs"
  fi

  lock_timeout="$(ask_input "Lock timeout" "5m")"
  [[ -n "$lock_timeout" ]] && args="${args} -lock-timeout=${lock_timeout}"

  printf '%s' "$args"
}

run_tf_with_args() {
  local subcommand="$1"
  shift
  local -a args=("$@")
  log_step "Running: ${TF_CMD} ${subcommand} ${args[*]:-}"
  run_cmd "$TF_CMD" "$subcommand" "${args[@]}"
}

split_args() {
  local arg_string="$1"
  local -n out_ref="$2"
  out_ref=()
  [[ -z "$arg_string" ]] && return 0
  # shellcheck disable=SC2206
  out_ref=($arg_string)
}

# ---------------------------------------------------------------------------
# TERRAFORM WORKFLOW
# ---------------------------------------------------------------------------
tf_init() {
  ensure_tf_dir || return 1
  local -a args=()
  if ask_confirm "Upgrade modules and providers during init?"; then
    args+=("-upgrade")
  fi
  run_tf_with_args init "${args[@]}"
  log_ok "Init complete."
}

tf_validate() {
  ensure_tf_dir || return 1
  run_tf_with_args validate
  log_ok "Validation complete."
}

tf_fmt() {
  ensure_tf_dir || return 1
  local mode
  menu_select "Format Terraform Files" "Back" \
    "1:Check formatting only" \
    "2:Format files in place"
  mode="$REPLY"
  case "$mode" in
    1) run_tf_with_args fmt -check -recursive ;;
    2) run_tf_with_args fmt -recursive ;;
    0) return 0 ;;
    *) log_warn "Invalid option." ;;
  esac
}

tf_plan() {
  ensure_tf_dir || return 1
  local plan_file common_arg_string
  local -a args=()

  common_arg_string="$(collect_common_args)"
  split_args "$common_arg_string" args

  plan_file="$(ask_input "Plan output file (leave empty for no file)" "tfplan")"
  if [[ -n "$plan_file" ]]; then
    args+=("-out=${plan_file}")
  fi

  run_tf_with_args plan "${args[@]}"
}

tf_apply() {
  ensure_tf_dir || return 1
  log_warn "This will APPLY changes to real infrastructure."

  local plan_file common_arg_string
  local -a args=()
  plan_file="$(ask_input "Existing plan file to apply (leave empty for normal apply)" "tfplan")"

  if [[ -n "$plan_file" && -f "$plan_file" ]]; then
    if ! ask_confirm "Apply plan file '$plan_file'?"; then log_warn "Cancelled."; return 0; fi
    run_tf_with_args apply "$plan_file"
    log_ok "Apply complete."
    return 0
  fi

  if [[ -n "$plan_file" && ! -f "$plan_file" ]]; then
    log_warn "Plan file not found: $plan_file"
  fi

  common_arg_string="$(collect_common_args)"
  split_args "$common_arg_string" args

  if ask_confirm "Use -auto-approve?"; then
    args+=("-auto-approve")
  else
    log_info "Terraform/OpenTofu will ask for confirmation interactively."
  fi

  if ! ask_confirm "Proceed with apply?"; then log_warn "Cancelled."; return 0; fi
  run_tf_with_args apply "${args[@]}"
  log_ok "Apply complete."
}

tf_destroy() {
  ensure_tf_dir || return 1
  log_warn "DESTROY will delete resources managed by this state."
  log_warn "Review the workspace and backend before continuing."
  "$TF_CMD" workspace show 2>/dev/null | sed 's/^/Current workspace: /' || true

  local common_arg_string typed
  local -a args=()
  common_arg_string="$(collect_common_args)"
  split_args "$common_arg_string" args

  if ! ask_confirm "First confirmation: proceed with destroy?"; then log_warn "Cancelled."; return 0; fi
  typed="$(ask_input "Type DESTROY to confirm")"
  if [[ "$typed" != "DESTROY" ]]; then
    log_warn "Cancelled."
    return 0
  fi

  if ask_confirm "Use -auto-approve?"; then
    args+=("-auto-approve")
  else
    log_info "Terraform/OpenTofu will ask for confirmation interactively."
  fi

  run_tf_with_args destroy "${args[@]}"
  log_ok "Destroy complete."
}

tf_output() {
  ensure_tf_dir || return 1
  local name
  name="$(ask_input "Output name (leave empty for all)" "")"
  if [[ -n "$name" ]]; then
    run_tf_with_args output "$name"
  else
    run_tf_with_args output
  fi
}

tf_graph() {
  ensure_tf_dir || return 1
  local outfile
  outfile="$(ask_input "Graph DOT output file" "terraform-graph.dot")"
  require_not_empty "$outfile" "Output file"
  if [[ -e "$outfile" ]] && ! ask_confirm "Overwrite '$outfile'?"; then
    log_warn "Cancelled."
    return 0
  fi

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    log_info "[DRY-RUN] Would write graph to: $outfile"
  else
    "$TF_CMD" graph > "$outfile"
  fi
  log_ok "Graph written to: $outfile"
  if is_installed dot && ask_confirm "Render PNG with graphviz dot?"; then
    run_cmd dot -Tpng "$outfile" -o "${outfile%.dot}.png"
    log_ok "PNG written to: ${outfile%.dot}.png"
  fi
}

# ---------------------------------------------------------------------------
# STATE / WORKSPACES
# ---------------------------------------------------------------------------
tf_state_menu() {
  ensure_tf_dir || return 1
  while true; do
    menu_select "State Management" "Back" \
      "1:List resources in state" \
      "2:Show resource details" \
      "3:Pull state to file" \
      "4:Remove resource from state" \
      "5:Move resource address in state"

    case "$REPLY" in
      1)
        run_tf_with_args state list
        pause
        ;;
      2)
        local res
        res="$(ask_input "Resource address")"
        require_not_empty "$res" "Resource address"
        run_tf_with_args state show "$res"
        pause
        ;;
      3)
        local outfile
        outfile="$(ask_input "Destination state file" "terraform-state.json")"
        require_not_empty "$outfile" "Destination state file"
        if [[ -e "$outfile" ]] && ! ask_confirm "Overwrite '$outfile'?"; then
          log_warn "Cancelled."
        elif [[ "${DRY_RUN:-0}" == "1" ]]; then
          log_info "[DRY-RUN] Would pull state to: $outfile"
        else
          "$TF_CMD" state pull > "$outfile"
          log_ok "State written to: $outfile"
        fi
        pause
        ;;
      4)
        local res
        res="$(ask_input "Resource address to remove from state")"
        require_not_empty "$res" "Resource address"
        log_warn "This removes the resource from state only. It does not delete the real resource."
        if ask_confirm "Remove '$res' from state?"; then
          run_tf_with_args state rm "$res"
          log_ok "Resource removed from state."
        fi
        pause
        ;;
      5)
        local from_addr to_addr
        from_addr="$(ask_input "Current resource address")"
        to_addr="$(ask_input "New resource address")"
        require_not_empty "$from_addr" "Current resource address"
        require_not_empty "$to_addr" "New resource address"
        if ask_confirm "Move state '$from_addr' to '$to_addr'?"; then
          run_tf_with_args state mv "$from_addr" "$to_addr"
          log_ok "State address moved."
        fi
        pause
        ;;
      0) return 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

tf_workspace_menu() {
  ensure_tf_dir || return 1
  while true; do
    echo
    log_info "Current workspace: $("$TF_CMD" workspace show 2>/dev/null || echo "unknown")"
    menu_select "Workspace Management" "Back" \
      "1:List workspaces" \
      "2:Create workspace" \
      "3:Switch workspace" \
      "4:Delete workspace"

    case "$REPLY" in
      1)
        run_tf_with_args workspace list
        pause
        ;;
      2)
        local ws
        ws="$(ask_input "New workspace name")"
        require_not_empty "$ws" "Workspace name"
        run_tf_with_args workspace new "$ws"
        pause
        ;;
      3)
        run_tf_with_args workspace list || true
        local ws
        ws="$(ask_input "Workspace to switch to")"
        require_not_empty "$ws" "Workspace name"
        run_tf_with_args workspace select "$ws"
        pause
        ;;
      4)
        run_tf_with_args workspace list || true
        local ws
        ws="$(ask_input "Workspace to delete")"
        require_not_empty "$ws" "Workspace name"
        if [[ "$ws" == "default" ]]; then
          log_error "Refusing to delete the default workspace."
        elif ask_confirm "Delete workspace '$ws'?"; then
          run_tf_with_args workspace delete "$ws"
        fi
        pause
        ;;
      0) return 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# PROJECT HELPERS
# ---------------------------------------------------------------------------
create_basic_project() {
  local dir
  dir="$(ask_input "Project directory" "$(pwd)/terraform-project")"
  require_not_empty "$dir" "Project directory"

  if [[ -e "$dir" ]] && [[ -n "$(find "$dir" -mindepth 1 -maxdepth 1 2>/dev/null)" ]]; then
    if ! ask_confirm "Directory exists and is not empty. Continue?"; then return 0; fi
  fi

  run_cmd mkdir -p "$dir"

  local main_tf="${dir}/main.tf"
  local versions_tf="${dir}/versions.tf"
  local variables_tf="${dir}/variables.tf"
  local outputs_tf="${dir}/outputs.tf"

  for file in "$main_tf" "$versions_tf" "$variables_tf" "$outputs_tf"; do
    if [[ -e "$file" ]] && ! ask_confirm "Overwrite '$file'?"; then
      log_warn "Skipped: $file"
      continue
    fi

    if [[ "${DRY_RUN:-0}" == "1" ]]; then
      log_info "[DRY-RUN] Would write: $file"
      continue
    fi

    case "$file" in
      "$main_tf")
        printf '%s\n' \
          'locals {' \
          '  project_name = var.project_name' \
          '}' \
          '' \
          '# Add providers and resources here.' > "$file"
        ;;
      "$versions_tf")
        printf '%s\n' \
          'terraform {' \
          '  required_version = ">= 1.5.0"' \
          '}' > "$file"
        ;;
      "$variables_tf")
        printf '%s\n' \
          'variable "project_name" {' \
          '  description = "Project name used for naming resources."' \
          '  type        = string' \
          '  default     = "example"' \
          '}' > "$file"
        ;;
      "$outputs_tf")
        printf '%s\n' \
          'output "project_name" {' \
          '  description = "Project name."' \
          '  value       = local.project_name' \
          '}' > "$file"
        ;;
    esac
  done

  log_ok "Basic project created in: $dir"
}

clean_local_cache() {
  ensure_tf_dir || return 1
  log_warn "This removes local Terraform cache files only:"
  echo "  - .terraform/"
  echo "  - .terraform.lock.hcl (optional)"
  echo "  - tfplan files matching your input"
  echo

  if ask_confirm "Remove .terraform directory?"; then
    run_cmd rm -rf .terraform
    log_ok "Removed .terraform directory."
  fi

  if [[ -f ".terraform.lock.hcl" ]] && ask_confirm "Remove .terraform.lock.hcl?"; then
    run_cmd rm -f .terraform.lock.hcl
    log_ok "Removed .terraform.lock.hcl."
  fi

  local plan_glob
  plan_glob="$(ask_input "Plan file to remove (leave empty to skip)" "tfplan")"
  if [[ -n "$plan_glob" && -e "$plan_glob" ]]; then
    if ask_confirm "Remove '$plan_glob'?"; then
      run_cmd rm -f "$plan_glob"
      log_ok "Removed: $plan_glob"
    fi
  fi
}

show_versions() {
  echo
  log_info "=== Versions ==="
  if is_installed terraform; then terraform version; else log_warn "terraform not installed"; fi
  echo
  if is_installed tofu; then tofu version; else log_warn "tofu not installed"; fi
  echo
}

# ---------------------------------------------------------------------------
# MENU
# ---------------------------------------------------------------------------
main_menu_choice() {
  if command -v dialog >/dev/null 2>&1; then
    menu_select "$SCRIPT_NAME" "Exit" \
      "1:Install Terraform" \
      "2:Install OpenTofu" \
      "3:Select tool" \
      "4:Show versions" \
      "5:init" \
      "6:fmt" \
      "7:validate" \
      "8:plan" \
      "9:apply" \
      "10:destroy (DESTRUCTIVE)" \
      "11:output" \
      "12:graph" \
      "13:state management" \
      "14:workspace management" \
      "15:create basic project" \
      "16:clean local cache" \
      "e:Show environment info"
    return 0
  fi

  echo "  ${BOLD}${YELLOW}Installation${RESET}"
  echo "  ${CYAN}1)${RESET}  Install Terraform"
  echo "  ${CYAN}2)${RESET}  Install OpenTofu"
  echo "  ${CYAN}3)${RESET}  Select tool"
  echo "  ${CYAN}4)${RESET}  Show versions"
  print_menu_separator
  echo "  ${BOLD}${YELLOW}Workflow ${DIM}(tool: ${TF_CMD:-not detected})${RESET}"
  echo "  ${CYAN}5)${RESET}  init"
  echo "  ${CYAN}6)${RESET}  fmt"
  echo "  ${CYAN}7)${RESET}  validate"
  echo "  ${CYAN}8)${RESET}  plan"
  echo "  ${CYAN}9)${RESET}  apply"
  echo "  ${CYAN}10)${RESET} destroy ${RED}(DESTRUCTIVE)${RESET}"
  echo "  ${CYAN}11)${RESET} output"
  echo "  ${CYAN}12)${RESET} graph"
  print_menu_separator
  echo "  ${BOLD}${YELLOW}State / Project${RESET}"
  echo "  ${CYAN}13)${RESET} state management"
  echo "  ${CYAN}14)${RESET} workspace management"
  echo "  ${CYAN}15)${RESET} create basic project"
  echo "  ${CYAN}16)${RESET} clean local cache"
  print_menu_separator
  echo "  ${CYAN}e)${RESET}  Show environment info"
  echo "  ${CYAN}0)${RESET}  Exit"
  echo
  read -r -p "Choose: " REPLY
}

main() {
  detect_tf_cmd

  while true; do
    print_script_header "$SCRIPT_NAME" "$SCRIPT_DESC"
    show_tf_status
    main_menu_choice
    c="$REPLY"
    echo

    case "${c:-}" in
      1)  install_terraform || true; pause ;;
      2)  install_opentofu || true; pause ;;
      3)  select_tf_cmd || true; pause ;;
      4)  show_versions || true; pause ;;
      5)  tf_init || true; pause ;;
      6)  tf_fmt || true; pause ;;
      7)  tf_validate || true; pause ;;
      8)  tf_plan || true; pause ;;
      9)  tf_apply || true; pause ;;
      10) tf_destroy || true; pause ;;
      11) tf_output || true; pause ;;
      12) tf_graph || true; pause ;;
      13) tf_state_menu || true; pause ;;
      14) tf_workspace_menu || true; pause ;;
      15) create_basic_project || true; pause ;;
      16) clean_local_cache || true; pause ;;
      e|E) show_env_info; pause ;;
      0) log_info "Bye!"; exit 0 ;;
      *) log_warn "Invalid option."; pause ;;
    esac
  done
}

main "$@"
