#!/usr/bin/env bash
# setup.sh — A-to-Z project environment provisioning (pure shell).
#
# Reads pyproject.toml automatically — no per-project JSON config required.
#
# Usage:
#   ./scripts/setup.sh
#   ./scripts/setup.sh --dry-run
#   ./scripts/setup.sh --steps conda,env,python,vscode,verify
#
# Optional machine-specific overrides:
#   scripts/setup/environment.local.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SETUP_DIR="${SCRIPT_DIR}/setup"

# shellcheck source=setup/common.sh
source "${SETUP_DIR}/common.sh"

parse_args "$@"

# shellcheck source=setup/pyproject.sh
source "${SETUP_DIR}/pyproject.sh"
# shellcheck source=setup/conda.sh
source "${SETUP_DIR}/conda.sh"
# shellcheck source=setup/python.sh
source "${SETUP_DIR}/python.sh"
# shellcheck source=setup/vscode.sh
source "${SETUP_DIR}/vscode.sh"
# shellcheck source=setup/verify.sh
source "${SETUP_DIR}/verify.sh"
# shellcheck source=setup/cicd.sh
source "${SETUP_DIR}/cicd.sh"

main() {
  log_step "Environment setup — $(basename "${PROJECT_ROOT}")"
  log_info "Project root: ${PROJECT_ROOT}"
  log_info "Setup dir:    ${SETUP_DIR}"

  load_local_overrides

  [[ "${SKIP_VSCODE}" == "1" ]] && export SETUP_SKIP_VSCODE=1

  load_pyproject_config

  if step_selected conda; then
    log_step "Conda bootstrap"
    ensure_miniconda
    update_conda
  fi

  if step_selected env; then
    log_step "Conda environment"
    ensure_conda_env
  fi

  if step_selected python; then
    log_step "Python packages"
    install_project_packages
  fi

  if step_selected vscode; then
    log_step "VS Code / Cursor workspace"
    setup_vscode
  fi

  if step_selected verify; then
    log_step "Verification"
    verify_setup
  fi

  if step_selected cicd; then
    log_step "CI/CD quality gates"
    run_cicd_gates
  fi

  log_step "Setup complete"
  log_ok "Conda env:  ${ENV_NAME} (${ENV_PREFIX})"
  log_ok "Python:     ${PYTHON_BIN}"
  log_ok "VS Code:    ${VSCODE_DIR}"
  log_info "Reload Cursor/VS Code window, then open a new terminal to use the ${ENV_NAME} profile."
}

main
