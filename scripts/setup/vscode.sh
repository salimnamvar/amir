#!/usr/bin/env bash
# Generate VS Code / Cursor workspace configuration from pyproject-derived settings.

if [[ -n "${SETUP_VSCODE_SH:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
SETUP_VSCODE_SH=1

_json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "${value}"
}

_write_vscode_settings() {
  local path="${VSCODE_DIR}/settings.json"
  local python_bin conda_bin pytest_bin profile_name analysis_path
  python_bin="$(_json_escape "${PYTHON_BIN}")"
  conda_bin="$(_json_escape "${CONDA_BIN}")"
  pytest_bin="$(_json_escape "${PYTEST_BIN}")"
  profile_name="$(_json_escape "${TERMINAL_PROFILE_NAME}")"
  analysis_path="$(_json_escape "${PYTHON_ANALYSIS_PATHS}")"

  if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "Would write ${path#"${PROJECT_ROOT}/"}"
    return 0
  fi

  mkdir -p "${VSCODE_DIR}"
  cat >"${path}" <<JSON
{
  "terminal.integrated.profiles.linux": {
    "${profile_name}": {
      "path": "/bin/bash",
      "args": ["--rcfile", "\${workspaceFolder}/.vscode/terminal-init.sh", "-i"],
      "icon": "beaker"
    },
    "bash": {
      "path": "/bin/bash",
      "icon": "terminal-bash"
    }
  },
  "terminal.integrated.defaultProfile.linux": "${profile_name}",
  "python.defaultInterpreterPath": "${python_bin}",
  "python.condaPath": "${conda_bin}",
  "python.terminal.activateEnvironment": true,
  "python.terminal.activateEnvInCurrentTerminal": true,
  "python.envFile": "\${workspaceFolder}/.env",
  "python.analysis.extraPaths": [
    "\${workspaceFolder}/${analysis_path}"
  ],
  "python.testing.pytestEnabled": true,
  "python.testing.unittestEnabled": false,
  "python.testing.pytestPath": "${pytest_bin}",
  "python.testing.pytestArgs": [
    "${PYTEST_TESTPATHS}"
  ],
  "python.testing.cwd": "\${workspaceFolder}",
  "[python]": {
    "editor.defaultFormatter": "charliermarsh.ruff",
    "editor.formatOnSave": true,
    "editor.codeActionsOnSave": {
      "source.fixAll.ruff": "explicit",
      "source.organizeImports.ruff": "explicit"
    }
  },
  "ruff.enable": true,
  "ruff.lint.args": [
    "--line-length=${RUFF_LINE_LENGTH}"
  ],
  "ruff.format.args": [
    "--line-length=${RUFF_LINE_LENGTH}"
  ],
  "python.analysis.typeCheckingMode": "strict",
  "python.analysis.diagnosticMode": "workspace",
  "files.exclude": {
    "**/__pycache__": true,
    "**/*.egg-info": true,
    "**/.ruff_cache": true,
    "**/.pytest_cache": true,
    "**/.mypy_cache": true,
    "**/.coverage*": true,
    "**/htmlcov": true,
    "**/build": true,
    "**/dist": true,
    "**/.eggs": true
  },
  "search.exclude": {
    "**/__pycache__": true,
    "**/*.egg-info": true,
    "**/.ruff_cache": true,
    "**/.pytest_cache": true,
    "**/.coverage*": true
  }
}
JSON

  log_ok "Wrote ${path#"${PROJECT_ROOT}/"}"
}

_write_vscode_launch() {
  local path="${VSCODE_DIR}/launch.json"
  local python_bin
  python_bin="$(_json_escape "${PYTHON_BIN}")"

  if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "Would write ${path#"${PROJECT_ROOT}/"}"
    return 0
  fi

  mkdir -p "${VSCODE_DIR}"
  cat >"${path}" <<JSON
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Python: Current File",
      "type": "debugpy",
      "request": "launch",
      "program": "\${file}",
      "console": "integratedTerminal",
      "cwd": "\${workspaceFolder}",
      "justMyCode": true,
      "python": "${python_bin}",
      "envFile": "\${workspaceFolder}/.env"
    },
    {
      "name": "Python: Module",
      "type": "debugpy",
      "request": "launch",
      "module": "enter.module.name.here",
      "console": "integratedTerminal",
      "cwd": "\${workspaceFolder}",
      "justMyCode": true,
      "python": "${python_bin}",
      "envFile": "\${workspaceFolder}/.env"
    },
    {
      "name": "Python: Pytest Current File",
      "type": "debugpy",
      "request": "launch",
      "module": "pytest",
      "args": ["\${file}", "-v"],
      "console": "integratedTerminal",
      "cwd": "\${workspaceFolder}",
      "justMyCode": false,
      "python": "${python_bin}",
      "envFile": "\${workspaceFolder}/.env"
    },
    {
      "name": "Python: Pytest All",
      "type": "debugpy",
      "request": "launch",
      "module": "pytest",
      "args": ["${PYTEST_TESTPATHS}", "-v"],
      "console": "integratedTerminal",
      "cwd": "\${workspaceFolder}",
      "justMyCode": false,
      "python": "${python_bin}",
      "envFile": "\${workspaceFolder}/.env"
    }
  ]
}
JSON

  log_ok "Wrote ${path#"${PROJECT_ROOT}/"}"
}

_write_vscode_tasks() {
  local path="${VSCODE_DIR}/tasks.json"
  local env_bin pip_target
  env_bin="$(_json_escape "${ENV_PREFIX}/bin")"
  pip_target="$(_json_escape "${PIP_INSTALL_TARGET}")"

  if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "Would write ${path#"${PROJECT_ROOT}/"}"
    return 0
  fi

  mkdir -p "${VSCODE_DIR}"
  cat >"${path}" <<JSON
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "pytest: all",
      "type": "shell",
      "command": "${env_bin}/pytest",
      "args": ["${PYTEST_TESTPATHS}", "-v"],
      "options": {
        "cwd": "\${workspaceFolder}",
        "env": {
          "PATH": "${env_bin}:\${env:PATH}"
        }
      },
      "problemMatcher": [],
      "group": {
        "kind": "test",
        "isDefault": true
      }
    },
    {
      "label": "pytest: coverage",
      "type": "shell",
      "command": "${env_bin}/pytest",
      "args": ["${PYTEST_TESTPATHS}", "--cov=${PYTHON_ANALYSIS_PATHS}", "--cov-report=term-missing"],
      "options": {
        "cwd": "\${workspaceFolder}",
        "env": {
          "PATH": "${env_bin}:\${env:PATH}"
        }
      },
      "problemMatcher": [],
      "group": "test"
    },
    {
      "label": "pip: install editable${PROJECT_HAS_DEV_EXTRAS:+ [dev]}",
      "type": "shell",
      "command": "${env_bin}/pip",
      "args": ["install", "-e", "${pip_target}"],
      "options": {
        "cwd": "\${workspaceFolder}",
        "env": {
          "PATH": "${env_bin}:\${env:PATH}"
        }
      },
      "problemMatcher": []
    },
    {
      "label": "ruff: check",
      "type": "shell",
      "command": "${env_bin}/ruff",
      "args": ["check", "${PYTHON_ANALYSIS_PATHS}", "${PYTEST_TESTPATHS}"],
      "options": {
        "cwd": "\${workspaceFolder}",
        "env": {
          "PATH": "${env_bin}:\${env:PATH}"
        }
      },
      "problemMatcher": []
    },
    {
      "label": "ruff: format",
      "type": "shell",
      "command": "${env_bin}/ruff",
      "args": ["format", "${PYTHON_ANALYSIS_PATHS}", "${PYTEST_TESTPATHS}"],
      "options": {
        "cwd": "\${workspaceFolder}",
        "env": {
          "PATH": "${env_bin}:\${env:PATH}"
        }
      },
      "problemMatcher": []
    },
    {
      "label": "pyright: strict check",
      "type": "shell",
      "command": "${env_bin}/pyright",
      "args": [],
      "options": {
        "cwd": "\${workspaceFolder}",
        "env": {
          "PATH": "${env_bin}:\${env:PATH}"
        }
      },
      "problemMatcher": [],
      "group": "build"
    },
    {
      "label": "lint: all (ruff+pyright)",
      "type": "shell",
      "command": "bash",
      "args": ["scripts/lint.sh"],
      "options": {
        "cwd": "\${workspaceFolder}",
        "env": {
          "PATH": "${env_bin}:\${env:PATH}"
        }
      },
      "problemMatcher": [],
      "group": "build"
    }
  ]
}
JSON

  log_ok "Wrote ${path#"${PROJECT_ROOT}/"}"
}

_write_vscode_extensions() {
  local path="${VSCODE_DIR}/extensions.json"

  if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "Would write ${path#"${PROJECT_ROOT}/"}"
    return 0
  fi

  mkdir -p "${VSCODE_DIR}"
  cat >"${path}" <<'JSON'
{
  "recommendations": [
    "ms-python.python",
    "ms-python.vscode-pylance",
    "ms-python.debugpy",
    "ms-python.black-formatter",
    "ms-python.isort",
    "astral-sh.ruff-vscode"
  ]
}
JSON

  log_ok "Wrote ${path#"${PROJECT_ROOT}/"}"
}

_write_terminal_init() {
  local path="${VSCODE_DIR}/terminal-init.sh"

  if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "Would write ${path#"${PROJECT_ROOT}/"}"
    return 0
  fi

  mkdir -p "${VSCODE_DIR}"
  cat >"${path}" <<TERMINAL
# Generated by scripts/setup_env.sh — do not edit by hand.
# Re-run setup to ConfigStoreenerate.
# Project terminal bootstrap: load shell config, then activate ${ENV_NAME}.
source "\${HOME}/.bashrc" 2>/dev/null || true

if [ -f "${CONDA_SH}" ]; then
  . "${CONDA_SH}"
  conda activate ${ENV_NAME} 2>/dev/null || true
fi
TERMINAL

  chmod 755 "${path}"
  log_ok "Wrote ${path#"${PROJECT_ROOT}/"}"
}

setup_vscode() {
  if [[ "${SETUP_SKIP_VSCODE:-0}" == "1" ]]; then
    log_info "Skipping VS Code setup (SETUP_SKIP_VSCODE=1)"
    return 0
  fi

  _write_vscode_settings
  _write_vscode_launch
  _write_vscode_tasks
  _write_vscode_extensions
  _write_terminal_init
}