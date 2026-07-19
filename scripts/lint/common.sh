#!/usr/bin/env bash
# Shared helpers for modular lint scripts.

if [[ -n "${SETUP_LINT_COMMON_SH:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
SETUP_LINT_COMMON_SH=1

set -euo pipefail

_RED='\033[0;31m'
_GREEN='\033[0;32m'
_YELLOW='\033[0;33m'
_CYAN='\033[0;36m'
_RESET='\033[0m'

lint_step() {
  printf "${_CYAN}==> %s${_RESET}\n" "$1" >&2
}

lint_ok() {
  printf "${_GREEN}   ✓ %s${_RESET}\n" "$1" >&2
}

lint_fail() {
  printf "${_RED}   ✗ %s${_RESET}\n" "$1" >&2
}

lint_warn() {
  printf "${_YELLOW}   ! %s${_RESET}\n" "$1" >&2
}

# Collect existing directories from arguments (skips missing ones).
lint_existing_dirs() {
  local d
  for d in "$@"; do
    [[ -d "${d}" ]] && printf '%s\n' "${d}"
  done
}
