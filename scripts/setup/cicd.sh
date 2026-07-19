#!/usr/bin/env bash
# CI/CD quality gates — see docs/RDM/08-quality-gates-cicd.md

if [[ -n "${SETUP_CICD_SH:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
SETUP_CICD_SH=1

_existing_code_paths() {
  local candidate
  local existing=()
  for candidate in "$@"; do
    if [[ -e "${PROJECT_ROOT}/${candidate}" ]]; then
      existing+=("${candidate}")
    fi
  done
  printf '%s\n' "${existing[@]}"
}

_run_tool_if_paths_exist() {
  local label="$1"
  local tool="$2"
  shift 2
  local static_args=("$@")
  local paths=()
  local path

  while IFS= read -r path; do
    [[ -n "${path}" ]] && paths+=("${path}")
  done < <(_existing_code_paths src tests)

  if [[ "${#paths[@]}" -eq 0 ]]; then
    log_info "Skipping ${label} (src/ and tests/ not present yet)"
    return 0
  fi

  if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "Would run: ${label} (${paths[*]})"
    return 0
  fi

  [[ -x "${tool}" ]] || die "Required tool not found: ${tool}"

  log_info "${label} ${paths[*]}"
  conda_runtime_env
  if ! (cd "${PROJECT_ROOT}" && "${tool}" "${static_args[@]}" "${paths[@]}"); then
    die "${label} failed"
  fi
  log_ok "${label}"
}

_run_pytest_layer() {
  local layer="$1"
  local path="${PROJECT_ROOT}/tests/${layer}"

  if [[ ! -d "${path}" ]]; then
    log_info "Skipping pytest ${layer} (no tests/${layer}/)"
    return 0
  fi

  if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "Would run: pytest tests/${layer}/ -v -m 'not live'"
    return 0
  fi

  # Exclude @pytest.mark.live (real OVMS/network); run those with: pytest -m live
  log_info "pytest tests/${layer}/ -v -m 'not live'"
  conda_runtime_env
  if ! (cd "${PROJECT_ROOT}" && "${PYTEST_BIN}" "tests/${layer}/" -v -m "not live"); then
    die "pytest tests/${layer}/ failed"
  fi
  log_ok "pytest tests/${layer}/"
}

_run_coverage_gate() {
  local src_path="${PROJECT_ROOT}/src/model_management"

  if [[ ! -d "${src_path}" ]] || [[ ! -d "${PROJECT_ROOT}/tests" ]]; then
    log_info "Skipping coverage gate (src/model_management or tests/ not present)"
    return 0
  fi

  if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "Would run: pytest --cov=src/model_management --cov-fail-under=80 -m 'not live'"
    return 0
  fi

  log_info "pytest --cov=src/model_management --cov-fail-under=80 -m 'not live'"
  conda_runtime_env
  if ! (cd "${PROJECT_ROOT}" && "${PYTEST_BIN}" --cov=src/model_management --cov-fail-under=80 -m "not live"); then
    die "Coverage gate failed"
  fi
  log_ok "Coverage gate passed"
}

_run_redocly_lint() {
  local spec="${PROJECT_ROOT}/docs/CT/API/openapi.yaml"

  if [[ ! -f "${spec}" ]]; then
    log_info "Skipping OpenAPI lint (docs/CT/API/openapi.yaml not found)"
    return 0
  fi

  if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "Would run: npx @redocly/cli lint --config docs/CT/API/redocly.yaml docs/CT/API/openapi.yaml"
    return 0
  fi

  if ! command -v npx >/dev/null 2>&1; then
    log_warn "Skipping OpenAPI lint (npx not available)"
    return 0
  fi

  log_info "npx @redocly/cli lint --config docs/CT/API/redocly.yaml docs/CT/API/openapi.yaml"
  if ! (cd "${PROJECT_ROOT}" && npx --yes @redocly/cli lint --config docs/CT/API/redocly.yaml docs/CT/API/openapi.yaml); then
    die "OpenAPI lint failed"
  fi
  log_ok "OpenAPI lint passed"
}

_run_pyright() {
  local pyright_bin="${ENV_PREFIX}/bin/pyright"

  if [[ ! -x "${pyright_bin}" ]]; then
    log_info "Skipping pyright (not installed in env)"
    return 0
  fi

  if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "Would run: pyright (strict)"
    return 0
  fi

  log_info "pyright (strict)"
  conda_runtime_env
  # Run from project root; pyright reads [tool.pyright] from pyproject.toml
  if ! (cd "${PROJECT_ROOT}" && "${pyright_bin}"); then
    die "pyright strict check failed"
  fi
  log_ok "pyright strict"
}

_run_comment_check() {
  # Lightweight guard against comment-overwhelmed code.
  # Fails if any .py under src/ or tests/ has high ratio of #-comment lines.
  # (Docstrings """ do not count; only # comments.)
  # Threshold chosen for "comments explain WHY, not restate WHAT".
  local py_files=()
  local p
  while IFS= read -r -d '' p; do py_files+=("$p"); done < <(find "${PROJECT_ROOT}/src" "${PROJECT_ROOT}/tests" -name "*.py" -print0 2>/dev/null | head -c 100000 || true)

  if [[ "${#py_files[@]}" -eq 0 ]]; then
    return 0
  fi

  if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "Would run: comment density check"
    return 0
  fi

  python - "$@" <<'PY' "${py_files[@]}" || die "comment density too high (overwhelming comments)"
import sys, pathlib
THRESHOLD = 0.30  # 30% pure comment lines is high
files = [pathlib.Path(f) for f in sys.argv[1:] if f]
bad = []
for f in files:
    try:
        text = f.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        continue
    lines = [ln for ln in text.splitlines()]
    non_blank = [ln for ln in lines if ln.strip()]
    if not non_blank:
        continue
    # count lines that start with optional ws + #
    comment_lines = sum(1 for ln in lines if ln.lstrip().startswith("#"))
    ratio = comment_lines / len(non_blank)
    if len(non_blank) >= 8 and ratio > THRESHOLD:
        bad.append((f, round(ratio*100)))
if bad:
    for path, pct in bad:
        print(f"Too many comments ({pct}%): {path.relative_to(path.parent.parent.parent)}", file=sys.stderr)
    sys.exit(1)
print("comment density ok")
PY
  log_ok "comment density"
}

run_cicd_gates() {
  # Static analysis (format, imports, lint, strict types) — all scoped inside this service
  local lint_script="${PROJECT_ROOT}/scripts/lint.sh"
  if [[ -x "${lint_script}" ]]; then
    log_info "scripts/lint.sh (ruff + pyright-strict)"
    if [[ "${DRY_RUN}" == "1" ]]; then
      log_info "Would run: ${lint_script}"
    else
      conda_runtime_env
      if ! (cd "${PROJECT_ROOT}" && "${lint_script}"); then
        die "lint script failed (see output above)"
      fi
      log_ok "ruff + pyright-strict"
    fi
  else
    # Fallback to individual tools (for older setups)
    _run_tool_if_paths_exist \
      "ruff check" \
      "${ENV_PREFIX}/bin/ruff" check

    _run_tool_if_paths_exist \
      "ruff format --check" \
      "${ENV_PREFIX}/bin/ruff" format --check

    _run_pyright
  fi

  _run_comment_check

  _run_pytest_layer unit
  _run_pytest_layer integration
  _run_pytest_layer api
  _run_redocly_lint
  _run_coverage_gate
}