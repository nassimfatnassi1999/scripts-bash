#!/usr/bin/env bash
# lint.sh — Validate toolbox shell scripts
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$ROOT_DIR"

status=0

log() { printf '[lint] %s\n' "$*"; }
warn() { printf '[lint][warn] %s\n' "$*" >&2; }
fail() { printf '[lint][fail] %s\n' "$*" >&2; status=1; }

mapfile -t shell_files < <(
  {
    printf '%s\n' "main.sh" "lint.sh" "lib/common.sh"
    find scripts -maxdepth 1 -type f -name '*.sh' -print
  } | sort -u
)

log "Checking bash syntax..."
for file in "${shell_files[@]}"; do
  if bash -n "$file"; then
    log "bash -n OK: $file"
  else
    fail "bash -n failed: $file"
  fi
done

if command -v shellcheck >/dev/null 2>&1; then
  log "Running ShellCheck..."
  if shellcheck "${shell_files[@]}"; then
    log "ShellCheck OK"
  else
    fail "ShellCheck found issues"
  fi
else
  warn "shellcheck not installed; skipped ShellCheck."
fi

if command -v shfmt >/dev/null 2>&1; then
  log "Checking shfmt formatting..."
  if shfmt -d "${shell_files[@]}"; then
    log "shfmt OK"
  else
    fail "shfmt found formatting differences"
  fi
else
  warn "shfmt not installed; skipped formatting check."
fi

log "Checking executable permissions..."
for file in main.sh lint.sh scripts/*.sh; do
  if [[ -x "$file" ]]; then
    log "executable OK: $file"
  else
    fail "not executable: $file"
  fi
done

if [[ "$status" -eq 0 ]]; then
  log "All checks completed successfully."
else
  fail "One or more checks failed."
fi

exit "$status"
