#!/usr/bin/env bash
# pylint_check.sh — Run pylint with Google pylintrc.
#
# Uses the Google pylintrc for naming conventions, docstring checks,
# and additional style validations not covered by ruff.

if [[ -n "${SETUP_LINT_PYLINT_CHECK_SH:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
SETUP_LINT_PYLINT_CHECK_SH=1

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

pylint_run() {
  local pylint_bin="${1:-pylint}"
  local project_root="${2:-.}"
  local pylintrc="${LINT_DIR}/pylintrc"

  lint_step "pylint (Google pylintrc)"

  if ! command -v "${pylint_bin}" >/dev/null 2>&1 && [[ ! -x "${pylint_bin}" ]]; then
    lint_warn "pylint not found: ${pylint_bin}, skipping"
    return 0
  fi

  if [[ ! -f "${pylintrc}" ]]; then
    lint_warn "pylintrc not found at ${pylintrc}, skipping"
    return 0
  fi

  # Run pylint with Google pylintrc on src/ only
  # --recursive=y to follow package structure
  # --fail-under=8 to allow some warnings without failing
  if ! "${pylint_bin}" \
    --rcfile="${pylintrc}" \
    --recursive=y \
    --fail-under=8 \
    "${project_root}/src" 2>&1; then
    lint_fail "pylint: issues found"
    return 1
  fi

  lint_ok "pylint (Google pylintrc)"
}

# When executed directly (not sourced), run with provided arguments.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  project_root="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
  pylint_run "${1:-pylint}" "${project_root}"
fi
