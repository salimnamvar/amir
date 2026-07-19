#!/usr/bin/env bash
# Shared helpers for setup_env modules.

if [[ -n "${SETUP_COMMON_SH:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
SETUP_COMMON_SH=1

set -euo pipefail

: "${PROJECT_ROOT:?PROJECT_ROOT must be set before sourcing common.sh}"
: "${SETUP_DIR:?SETUP_DIR must be set before sourcing common.sh}"

DRY_RUN="${DRY_RUN:-0}"
RECREATE_ENV="${RECREATE_ENV:-0}"
SKIP_VERIFY="${SKIP_VERIFY:-0}"
SKIP_VSCODE="${SKIP_VSCODE:-0}"
SKIP_CICD="${SKIP_CICD:-0}"

ALL_STEPS=(conda env python vscode verify cicd)
SELECTED_STEPS=()

log_step() {
  printf '\n── %s ──\n' "$1" >&2
}

log_info() {
  local suffix=""
  [[ "${DRY_RUN}" == "1" ]] && suffix=" [dry-run]"
  printf '· %s%s\n' "$1" >&2
}

log_ok() {
  local suffix=""
  [[ "${DRY_RUN}" == "1" ]] && suffix=" [dry-run]"
  printf '✓ %s%s\n' "$1" >&2
}

log_warn() {
  printf '! %s\n' "$1" >&2
}

log_error() {
  printf '✗ %s\n' "$1" >&2
}

die() {
  log_error "$1"
  exit 1
}

run_cmd() {
  local display=""
  display="$(printf '%q ' "$@")"
  display="${display% }"
  log_info "${display}"

  if [[ "${DRY_RUN}" == "1" ]]; then
    return 0
  fi

  "$@"
}

step_selected() {
  local step="$1"
  local selected
  for selected in "${SELECTED_STEPS[@]}"; do
    if [[ "${selected}" == "${step}" ]]; then
      return 0
    fi
  done
  return 1
}

load_local_overrides() {
  local local_file="${SETUP_DIR}/environment.local.sh"
  if [[ -f "${local_file}" ]]; then
    # shellcheck source=/dev/null
    source "${local_file}"
    log_info "Loaded local overrides: ${local_file}"
  fi
}

conda_runtime_env() {
  export PATH="${ENV_PREFIX}/bin:${CONDA_DIR}/bin:${CONDA_DIR}/condabin:${PATH}"
  export CONDA_PREFIX="${ENV_PREFIX}"
  export CONDA_DEFAULT_ENV="${ENV_NAME}"
  export CONDA_PROMPT_MODIFIER="(${ENV_NAME}) "
}

detect_platform() {
  local system
  system="$(uname -s | tr '[:upper:]' '[:lower:]')"
  case "${system}" in
    linux) echo "linux" ;;
    darwin) echo "darwin" ;;
    *) die "Unsupported platform: ${system}" ;;
  esac
}

parse_args() {
  SELECTED_STEPS=("${ALL_STEPS[@]}")

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --recreate)
        RECREATE_ENV=1
        shift
        ;;
      --skip-verify)
        SKIP_VERIFY=1
        shift
        ;;
      --skip-vscode)
        SKIP_VSCODE=1
        shift
        ;;
      --skip-cicd)
        SKIP_CICD=1
        shift
        ;;
      --steps)
        [[ $# -ge 2 ]] || die "--steps requires a comma-separated value"
        IFS=',' read -r -a SELECTED_STEPS <<< "$2"
        shift 2
        ;;
      -h|--help)
        cat <<'HELP'
setup_env.sh — A-to-Z project environment provisioning (pure shell).

Usage:
  ./scripts/setup_env.sh                     # create env if missing; update packages
  ./scripts/setup_env.sh --recreate          # wipe and rebuild the conda env
  ./scripts/setup_env.sh --dry-run
  ./scripts/setup_env.sh --steps conda,env,python,vscode,verify,cicd
  ./scripts/setup_env.sh --skip-verify
  ./scripts/setup_env.sh --skip-vscode
  ./scripts/setup_env.sh --skip-cicd

Configuration is read automatically from pyproject.toml.
Optional machine-specific overrides:
  scripts/setup/environment.local.sh

Environment variable overrides (also settable in environment.local.sh):
  SETUP_CONDA_DIR          Conda installation directory (default: $HOME/miniconda3)
  SETUP_ENV_NAME           Conda environment name (default: derived from project.name)
  SETUP_SKIP_CONDA_INSTALL Set to 1 to skip Miniconda bootstrap
  RECREATE_ENV             Set to 1 to wipe and rebuild the conda env
HELP
        exit 0
        ;;
      *)
        die "Unknown argument: $1 (use --help)"
        ;;
    esac
  done

  if [[ "${SKIP_VERIFY}" == "1" ]]; then
    local filtered=()
    local step
    for step in "${SELECTED_STEPS[@]}"; do
      [[ "${step}" != "verify" ]] && filtered+=("${step}")
    done
    SELECTED_STEPS=("${filtered[@]}")
  fi

  if [[ "${SKIP_VSCODE}" == "1" ]]; then
    local filtered=()
    local step
    for step in "${SELECTED_STEPS[@]}"; do
      [[ "${step}" != "vscode" ]] && filtered+=("${step}")
    done
    SELECTED_STEPS=("${filtered[@]}")
  fi

  if [[ "${SKIP_CICD}" == "1" ]]; then
    local filtered=()
    local step
    for step in "${SELECTED_STEPS[@]}"; do
      [[ "${step}" != "cicd" ]] && filtered+=("${step}")
    done
    SELECTED_STEPS=("${filtered[@]}")
  fi

  local step
  for step in "${SELECTED_STEPS[@]}"; do
    step="${step//[[:space:]]/}"
    local known=0
    local candidate
    for candidate in "${ALL_STEPS[@]}"; do
      if [[ "${step}" == "${candidate}" ]]; then
        known=1
        break
      fi
    done
    [[ "${known}" == "1" ]] || die "Unknown step: ${step}"
  done
}