#!/usr/bin/env bash
# pyright — strict static type checking.

if [[ -n "${SETUP_LINT_PYRIGHT_SH:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
SETUP_LINT_PYRIGHT_SH=1

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

pyright_run() {
  local pyright_bin="${1:-pyright}"
  local project_root="${2:-.}"

  lint_step "pyright (strict)"

  if ! command -v "${pyright_bin}" >/dev/null 2>&1 && [[ ! -x "${pyright_bin}" ]]; then
    lint_warn "pyright not found: ${pyright_bin}, skipping"
    return 0
  fi

  ( cd "${project_root}" && "${pyright_bin}" )
  lint_ok "pyright strict"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  project_root="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
  pyright_run "${1:-pyright}" "${project_root}"
fi
