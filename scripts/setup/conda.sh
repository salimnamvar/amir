#!/usr/bin/env bash
# Conda bootstrap and environment provisioning.

if [[ -n "${SETUP_CONDA_SH:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
SETUP_CONDA_SH=1

_miniconda_installer_url() {
  local platform arch
  platform="$(detect_platform)"
  arch="$(uname -m)"
  case "${platform}" in
    linux) printf 'https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-%s.sh' "${arch}" ;;
    darwin) printf 'https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-%s.sh' "${arch}" ;;
  esac
}

ensure_miniconda() {
  if [[ "${SETUP_SKIP_CONDA_INSTALL:-0}" == "1" ]]; then
    log_info "Skipping Miniconda install (SETUP_SKIP_CONDA_INSTALL=1)"
    return 0
  fi

  if [[ -x "${CONDA_BIN}" ]]; then
    log_ok "Miniconda found: ${CONDA_DIR}"
    return 0
  fi

  log_info "Miniconda not found at ${CONDA_DIR}; installing"
  if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "Would download installer from $(_miniconda_installer_url)"
    return 0
  fi

  local installer_url installer_path
  installer_url="$(_miniconda_installer_url)"
  installer_path="$(mktemp /tmp/miniconda_installer.XXXXXX.sh)"
  trap 'rm -f "${installer_path}"' RETURN

  mkdir -p "$(dirname "${CONDA_DIR}")"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "${installer_url}" -o "${installer_path}"
  elif command -v wget >/dev/null 2>&1; then
    wget -q "${installer_url}" -O "${installer_path}"
  else
    die "curl or wget is required to download Miniconda"
  fi

  run_cmd bash "${installer_path}" -b -p "${CONDA_DIR}"

  run_cmd "${CONDA_BIN}" config --set auto_activate_base false

  local channel
  for channel in \
    "https://repo.anaconda.com/pkgs/main" \
    "https://repo.anaconda.com/pkgs/r"
  do
    run_cmd "${CONDA_BIN}" tos accept --override-channels --channel "${channel}" || true
  done

  log_ok "Miniconda installed at ${CONDA_DIR}"
}

update_conda() {
  [[ -x "${CONDA_BIN}" ]] || die "conda binary not found: ${CONDA_BIN}"

  run_cmd "${CONDA_BIN}" update -n base conda -y --quiet

  if [[ "${DRY_RUN}" == "1" ]]; then
    return 0
  fi

  local version
  version="$("${CONDA_BIN}" --version 2>/dev/null || true)"
  [[ -n "${version}" ]] && log_ok "${version}"
}

ensure_conda_env() {
  [[ -x "${CONDA_BIN}" ]] || die "conda binary not found: ${CONDA_BIN}"

  if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "Would ensure conda env '${ENV_NAME}' with Python ${PROJECT_PYTHON_VERSION}"
    return 0
  fi

  if [[ -d "${ENV_PREFIX}" && "${RECREATE_ENV}" == "1" ]]; then
    log_info "Removing conda env '${ENV_NAME}' (--recreate)"
    run_cmd "${CONDA_BIN}" env remove -n "${ENV_NAME}" -y || true
    log_ok "Removed conda env: ${ENV_NAME}"
  fi

  if [[ ! -d "${ENV_PREFIX}" ]]; then
    run_cmd "${CONDA_BIN}" create -n "${ENV_NAME}" \
      "python=${PROJECT_PYTHON_VERSION}" pip -y --quiet \
      -c conda-forge -c defaults
    log_ok "Created conda env: ${ENV_NAME} (Python ${PROJECT_PYTHON_VERSION})"
  else
    log_ok "Conda env already exists: ${ENV_NAME} (${ENV_PREFIX})"
  fi

  if [[ ! -x "${PIP_BIN}" ]]; then
    log_info "pip missing in ${ENV_NAME}; installing"
    run_cmd "${CONDA_BIN}" install -n "${ENV_NAME}" pip -y --quiet
  fi

  [[ -x "${PIP_BIN}" ]] || die "pip not available in conda env: ${ENV_PREFIX}"
}