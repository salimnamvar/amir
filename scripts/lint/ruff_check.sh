#!/usr/bin/env bash
# ruff check — lint for Python errors and style.

if [[ -n "${SETUP_LINT_RUFF_CHECK_SH:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
SETUP_LINT_RUFF_CHECK_SH=1

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ruff_check_run() {
  local ruff_bin="${1:-ruff}"
  shift
  local dirs=("$@")

  lint_step "ruff check ${dirs[*]}"

  if ! command -v "${ruff_bin}" >/dev/null 2>&1 && [[ ! -x "${ruff_bin}" ]]; then
    lint_fail "ruff not found: ${ruff_bin}"
    return 1
  fi

  "${ruff_bin}" check "${dirs[@]}"
  lint_ok "ruff check"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  ruff_check_run "$@"
fi
