#!/usr/bin/env bash
# Post-setup verification.

if [[ -n "${SETUP_VERIFY_SH:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
SETUP_VERIFY_SH=1

_verify_command() {
  local name="$1"
  shift
  local binary="${ENV_PREFIX}/bin/${name}"

  if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "Would verify: ${name} $*"
    return 0
  fi

  local output=""
  if ! output="$("${binary}" "$@" 2>&1)"; then
    die "Verification failed for ${name} $*: ${output}"
  fi

  local summary
  summary="$(printf '%s\n' "${output}" | head -n 1)"
  log_ok "${name}: ${summary:-ok}"
}

verify_setup() {
  conda_runtime_env

  _verify_command python --version
  _verify_command pytest --version
  _verify_command pip check

  if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "Would run: pytest --collect-only -q"
    return 0
  fi

  local output=""
  local rc=0
  output="$("${PYTEST_BIN}" --collect-only -q 2>&1)" || rc=$?

  if [[ "${rc}" -ne 0 && "${rc}" -ne 5 ]]; then
    die "pytest collection failed: ${output}"
  fi

  local summary
  summary="$(printf '%s\n' "${output}" | tail -n 1)"
  if [[ "${rc}" -eq 5 ]]; then
    log_warn "${summary:-no tests collected}"
  else
    log_ok "${summary:-pytest collection ok}"
  fi
}