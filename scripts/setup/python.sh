#!/usr/bin/env bash
# Python package installation inside the project conda environment.

if [[ -n "${SETUP_PYTHON_SH:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
SETUP_PYTHON_SH=1

install_project_packages() {
  [[ -f "${PYPROJECT_PATH}" ]] || die "pyproject.toml not found: ${PYPROJECT_PATH}"

  if [[ "${DRY_RUN}" != "1" && ! -x "${PYTHON_BIN}" ]]; then
    die "Python interpreter not found: ${PYTHON_BIN}"
  fi

  conda_runtime_env

  run_cmd "${PIP_BIN}" install --upgrade pip setuptools wheel

  if [[ "${PROJECT_HAS_DEV_EXTRAS}" == "1" ]]; then
    run_cmd "${PIP_BIN}" install --upgrade -e "${PIP_INSTALL_TARGET}"
  else
    run_cmd "${PIP_BIN}" install --upgrade -e .
  fi

  log_ok "Installed project packages into ${ENV_NAME}"
}