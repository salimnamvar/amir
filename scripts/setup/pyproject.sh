#!/usr/bin/env bash
# Parse pyproject.toml into shell variables (no Python dependency).

if [[ -n "${SETUP_PYPROJECT_SH:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
SETUP_PYPROJECT_SH=1

PYPROJECT_PATH="${PROJECT_ROOT}/pyproject.toml"

# Populated by load_pyproject_config:
#   PROJECT_NAME, PROJECT_PYTHON_VERSION, PROJECT_HAS_DEV_EXTRAS
#   RUFF_LINE_LENGTH, RUFF_TARGET
#   PYTEST_TESTPATHS, PYTHON_ANALYSIS_PATHS

_parse_pyproject_toml() {
  local file="$1"
  [[ -f "${file}" ]] || die "pyproject.toml not found: ${file}"

  local output
  output="$(
    awk '
      function trim(s) {
        sub(/^[ \t]+/, "", s)
        sub(/[ \t]+$/, "", s)
        return s
      }

      function unquote(s) {
        if (s ~ /^".*"$/) {
          sub(/^"/, "", s)
          sub(/"$/, "", s)
        } else if (s ~ /^'\''.*'\''$/) {
          sub(/^'\''/, "", s)
          sub(/'\''$/, "", s)
        }
        return s
      }

      function strip_comment(s) {
        if (match(s, /[ \t]#/)) {
          s = substr(s, 1, RSTART - 1)
        }
        return trim(s)
      }

      function emit(key, value) {
        gsub(/\\/, "\\\\", value)
        gsub(/"/, "\\\"", value)
        printf "%s=\"%s\"\n", key, value
      }

      BEGIN {
        section = ""
        in_dev_array = 0
      }

      /^[ \t]*#/ { next }
      /^[ \t]*$/ { next }

      /^\[/ {
        line = $0
        gsub(/^[ \t]*\[/, "", line)
        gsub(/\][ \t]*$/, "", line)
        section = line
        in_dev_array = 0
        next
      }

      {
        line = $0
        sub(/^[ \t]+/, "", line)

        if (section == "project" && match(line, /^name[ \t]*=[ \t]*/)) {
          value = substr(line, RSTART + RLENGTH)
          emit("PROJECT_NAME", unquote(strip_comment(value)))
          next
        }

        if (section == "project" && match(line, /^requires-python[ \t]*=[ \t]*/)) {
          value = substr(line, RSTART + RLENGTH)
          emit("PROJECT_REQUIRES_PYTHON", unquote(strip_comment(value)))
          next
        }

        if (section == "project.optional-dependencies") {
          if (match(line, /^dev[ \t]*=[ \t]*\[/)) {
            emit("PROJECT_HAS_DEV_EXTRAS", "1")
            in_dev_array = 1
            next
          }
          if (in_dev_array) {
            if (line ~ /\]/) { in_dev_array = 0 }
            next
          }
        }

        if (section == "tool.ruff" && match(line, /^line-length[ \t]*=[ \t]*/)) {
          value = substr(line, RSTART + RLENGTH)
          emit("RUFF_LINE_LENGTH", unquote(strip_comment(value)))
          next
        }

        if (section == "tool.ruff" && match(line, /^target-version[ \t]*=[ \t]*/)) {
          value = substr(line, RSTART + RLENGTH)
          value = unquote(strip_comment(value))
          gsub(/^"/, "", value)
          gsub(/"$/, "", value)
          emit("RUFF_TARGET", value)
          next
        }

        if (section == "tool.pytest.ini_options" && match(line, /^testpaths[ \t]*=[ \t]*\[/)) {
          value = substr(line, RSTART + RLENGTH)
          sub(/\].*$/, "", value)
          value = strip_comment(value)
          gsub(/^[ \t]*"/, "", value)
          gsub(/".*$/, "", value)
          emit("PYTEST_TESTPATHS", value)
          next
        }

        if (section == "tool.setuptools.packages.find" && match(line, /^include[ \t]*=[ \t]*\[/)) {
          value = substr(line, RSTART + RLENGTH)
          sub(/\].*$/, "", value)
          value = strip_comment(value)
          gsub(/^[ \t]*"/, "", value)
          gsub(/".*$/, "", value)
          gsub(/\*$/, "", value)
          emit("PACKAGE_INCLUDE_GLOB", value)
          next
        }
      }
    ' "${file}"
  )"

  # shellcheck disable=SC1090
  eval "${output}"
}

_extract_python_version() {
  local spec="$1"
  local version=""

  if [[ "${spec}" =~ ([0-9]+\.[0-9]+) ]]; then
    version="${BASH_REMATCH[1]}"
  fi

  if [[ -z "${version}" ]]; then
    die "Could not parse requires-python from pyproject.toml: ${spec}"
  fi

  printf '%s' "${version}"
}

_sanitize_env_name() {
  local name="$1"
  name="${name,,}"
  name="${name//-/_}"
  name="${name//./_}"
  printf '%s' "${name}"
}

_derive_analysis_paths() {
  local include_glob="${PACKAGE_INCLUDE_GLOB:-src*}"
  local path="${include_glob%\*}"

  if [[ -z "${path}" || "${path}" == "${include_glob}" ]]; then
    path="src"
  fi

  PYTHON_ANALYSIS_PATHS="${path}"
}

load_pyproject_config() {
  _parse_pyproject_toml "${PYPROJECT_PATH}"

  [[ -n "${PROJECT_NAME:-}" ]] || die "Missing [project].name in pyproject.toml"
  [[ -n "${PROJECT_REQUIRES_PYTHON:-}" ]] || die "Missing [project].requires-python in pyproject.toml"

  PROJECT_PYTHON_VERSION="$(_extract_python_version "${PROJECT_REQUIRES_PYTHON}")"

  BLACK_LINE_LENGTH="${BLACK_LINE_LENGTH:-120}"
  BLACK_TARGET="${BLACK_TARGET:-py${PROJECT_PYTHON_VERSION//./}}"
  RUFF_LINE_LENGTH="${RUFF_LINE_LENGTH:-${BLACK_LINE_LENGTH}}"
  RUFF_TARGET="${RUFF_TARGET:-py${PROJECT_PYTHON_VERSION//./}}"
  PYTEST_TESTPATHS="${PYTEST_TESTPATHS:-tests}"
  PROJECT_HAS_DEV_EXTRAS="${PROJECT_HAS_DEV_EXTRAS:-0}"

  _derive_analysis_paths

  CONDA_DIR="${SETUP_CONDA_DIR:-${HOME}/miniconda3}"
  ENV_NAME="${SETUP_ENV_NAME:-$(_sanitize_env_name "${PROJECT_NAME}")}"

  CONDA_BIN="${CONDA_DIR}/bin/conda"
  CONDA_SH="${CONDA_DIR}/etc/profile.d/conda.sh"
  ENV_PREFIX="${CONDA_DIR}/envs/${ENV_NAME}"
  PYTHON_BIN="${ENV_PREFIX}/bin/python"
  PIP_BIN="${ENV_PREFIX}/bin/pip"
  PYTEST_BIN="${ENV_PREFIX}/bin/pytest"
  VSCODE_DIR="${PROJECT_ROOT}/.vscode"
  TERMINAL_PROFILE_NAME="${ENV_NAME} (conda)"

  if [[ "${PROJECT_HAS_DEV_EXTRAS}" == "1" ]]; then
    PIP_INSTALL_TARGET=".[dev]"
  else
    PIP_INSTALL_TARGET="."
  fi

  log_info "Project:        ${PROJECT_NAME}"
  log_info "Python:         ${PROJECT_PYTHON_VERSION} (${PROJECT_REQUIRES_PYTHON})"
  log_info "Conda env:      ${ENV_NAME}"
  log_info "Dev extras:     ${PROJECT_HAS_DEV_EXTRAS}"
  log_info "Ruff line-len:  ${RUFF_LINE_LENGTH}"
  log_info "Pytest paths:   ${PYTEST_TESTPATHS}"
  log_info "Analysis paths: ${PYTHON_ANALYSIS_PATHS}"
}