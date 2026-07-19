#!/usr/bin/env bash
# Comprehensive lint + format + type check for *this service only*.
# Operates on src/, tests/, and scripts/ relative to the service dir.
# Run from anywhere, or via: bash scripts/lint.sh
#
# Checks (in order):
#   1. ruff check       — lint for errors and style
#   2. ruff format      — enforce formatting (120 chars, double quotes)
#   3. a-prefix check   — all args must start with a_
#   4. import check     — no imports inside functions
#   5. return check     — single return per function (no early returns)
#   6. global check     — no mutable global state
#   7. google style     — docstrings, TODOs, function length, mutable defaults
#   8. pylint           — Google pylintrc for naming and style
#   9. pyright          — strict static type checking
#
# Used by:
#   - developers (manual)
#   - setup.sh --steps cicd  (via cicd.sh)
#   - .githooks/pre-commit (if present)
#
# Requires the conda env activated (or full path to the tools in env).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LINT_DIR="${SCRIPT_DIR}/lint"

# Allow caller to override (e.g. from cicd.sh)
: "${RUFF:=$(command -v ruff || echo ruff)}"
: "${PYRIGHT:=$(command -v pyright || echo pyright)}"
: "${PYLINT:=$(command -v pylint || echo pylint)}"

SRC_DIR="${SERVICE_ROOT}/src"
TESTS_DIR="${SERVICE_ROOT}/tests"
SCRIPTS_DIR="${SERVICE_ROOT}/scripts"

# Source modular lint scripts
# shellcheck source=lint/common.sh
source "${LINT_DIR}/common.sh"
# shellcheck source=lint/ruff_check.sh
source "${LINT_DIR}/ruff_check.sh"
# shellcheck source=lint/ruff_format.sh
source "${LINT_DIR}/ruff_format.sh"
# shellcheck source=lint/a_prefix_check.sh
source "${LINT_DIR}/a_prefix_check.sh"
# shellcheck source=lint/import_check.sh
source "${LINT_DIR}/import_check.sh"
# shellcheck source=lint/return_check.sh
source "${LINT_DIR}/return_check.sh"
# shellcheck source=lint/global_check.sh
source "${LINT_DIR}/global_check.sh"
# shellcheck source=lint/google_style_check.sh
source "${LINT_DIR}/google_style_check.sh"
# shellcheck source=lint/pylint_check.sh
source "${LINT_DIR}/pylint_check.sh"
# shellcheck source=lint/pyright.sh
source "${LINT_DIR}/pyright.sh"

# Start from a clean slate (removes stale caches, egg-info, pyc etc.)
if [[ -x "${SERVICE_ROOT}/scripts/clean.sh" ]]; then
  "${SERVICE_ROOT}/scripts/clean.sh"
fi

# Collect existing directories
dirs=()
while IFS= read -r d; do
  dirs+=("${d}")
done < <(lint_existing_dirs "${SRC_DIR}" "${TESTS_DIR}" "${SCRIPTS_DIR}")

if [[ ${#dirs[@]} -eq 0 ]]; then
  lint_warn "No src/ or tests/ directories found, nothing to lint"
  exit 0
fi

# Run all checks
ruff_check_run "${RUFF}" "${dirs[@]}"
ruff_format_run "${RUFF}" "${dirs[@]}"
a_prefix_check_run "${SRC_DIR}"
import_check_run "${SRC_DIR}"
return_check_run "${SRC_DIR}"
global_check_run "${SRC_DIR}"
google_style_check_run "${SRC_DIR}"
pylint_run "${PYLINT}" "${SERVICE_ROOT}"
pyright_run "${PYRIGHT}" "${SERVICE_ROOT}"

lint_ok "all checks passed (ruff-check, ruff-format, a-prefix, import, return, global, google-style, pylint, pyright)"
