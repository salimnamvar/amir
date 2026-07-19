#!/usr/bin/env bash
# global_check.sh — Prohibit mutable global state per Google Style Guide 2.5.
#
# Mutable globals break encapsulation and make code hard to test.
# Module-level constants (UPPER_CASE) are allowed.
# Framework globals (logger, app, etc.) are flagged for review.
#
# Uses awk to scan Python files for module-level mutable assignments.

if [[ -n "${SETUP_LINT_GLOBAL_CHECK_SH:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
SETUP_LINT_GLOBAL_CHECK_SH=1

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

_GLOBAL_CHECK_AWK='
BEGIN {
    in_func = 0
    func_depth = 0
    in_class = 0
    class_depth = 0
    in_import_block = 0
    in_type_checking = 0
    violations = 0
}

# Track function/method scope
/^[[:space:]]*(async[[:space:]]+)?def[[:space:]]+/ {
    in_func = 1
    func_depth = 0
    line = $0
    gsub(/[^[:space:]].*$/, "", line)
    func_indent = length(line)
    next
}

# Track class scope
/^[[:space:]]*class[[:space:]]+/ {
    in_class = 1
    line = $0
    gsub(/[^[:space:]].*$/, "", line)
    class_indent = length(line)
    next
}

# Track import blocks (skip them)
/^[[:space:]]*import[[:space:]]/ || /^[[:space:]]*from[[:space:]]/ {
    if (!in_func && !in_class) {
        in_import_block = 1
    }
    next
}

# Track TYPE_CHECKING blocks
/^[[:space:]]*if[[:space:]]+.*TYPE_CHECKING/ {
    in_type_checking = 1
    next
}

# Blank lines reset import block tracking
/^[[:space:]]*$/ {
    in_import_block = 0
    next
}

# Skip comments
/^[[:space:]]*#/ { next }

# Skip if inside function, class, import block, or TYPE_CHECKING
in_func { next }
in_class { next }
in_import_block { next }
in_type_checking { next }

# Skip __all__, __version__, and other dunder assignments
/^[[:space:]]*__[a-z][a-z0-9_]*__[[:space:]]*=/ { next }

# Skip _name = (private module-level, common for constants)
/^[[:space:]]*_[A-Z][A-Z0-9_]*[[:space:]]*=/ { next }

# Allow UPPER_CASE constants (Google Style 3.16.4)
/^[[:space:]]*[A-Z][A-Z0-9_]*[[:space:]]*=/ {
    line = $0
    if (line ~ /= *\[/ || line ~ /= *\{/ || line ~ /= *set\(/ ||
        line ~ /= *list\(/ || line ~ /= *dict\(/ || line ~ /= *collections\./) {
        printf "%d:0: error: mutable global constant must use private _ prefix (global-mutable)\n", NR
        violations++
    }
    next
}

# Detect non-UPPER module-level assignments (outside functions/classes)
/^[[:space:]]*[a-z][a-z0-9_]*[[:space:]]*=/ {
    line = $0
    match(line, /^[[:space:]]*[a-z][a-z0-9_]*/)
    varname = substr(line, RSTART, RLENGTH)
    gsub(/^[[:space:]]+/, "", varname)

    # Skip common framework globals
    if (varname == "logger" || varname == "log" || varname == "app" ||
        varname == "router" || varname == "db" || varname == "engine" ||
        varname == "session" || varname == "config" || varname == "settings" ||
        varname == "base" || varname == "Base" || varname == "metadata") {
        printf "%d:0: warning: framework global \"%s\" — ensure this is intentional (global-framework)\n", NR, varname
        next
    }

    # Mutable assignments are violations
    if (line ~ /= *\[/ || line ~ /= *\{/ || line ~ /= *set\(/ ||
        line ~ /= *list\(/ || line ~ /= *dict\(/ || line ~ /\[.+\] *=/ ||
        line ~ /\{.+\} *=/) {
        printf "%d:0: error: mutable global variable \"%s\" — use function scope or class attribute (global-mutable)\n", NR, varname
        violations++
    }
}

END { exit (violations > 0) ? 1 : 0 }
'

global_check_run() {
  local dirs=("$@")

  if [[ ${#dirs[@]} -eq 0 ]]; then
    lint_warn "global-check: no directories provided, skipping"
    return 0
  fi

  lint_step "mutable global state check ${dirs[*]}"

  local py_files=()
  local d
  for d in "${dirs[@]}"; do
    while IFS= read -r -d '' f; do
      py_files+=("$f")
    done < <(find "${d}" -name "*.py" -type f -not -name "__init__.py" -print0 2>/dev/null)
  done

  if [[ ${#py_files[@]} -eq 0 ]]; then
    lint_warn "global-check: no .py files found"
    return 0
  fi

  local has_violations=0
  local f
  for f in "${py_files[@]}"; do
    local output
    local rc=0
    output=$(awk "${_GLOBAL_CHECK_AWK}" "${f}" 2>/dev/null) || rc=$?
    if [[ ${rc} -ne 0 ]]; then
      while IFS= read -r line; do
        printf "%s:%s\n" "${f}" "${line}"
      done <<< "${output}"
      has_violations=1
    fi
  done

  if [[ "${has_violations}" -eq 1 ]]; then
    lint_fail "global-check: mutable global state violations found"
    return 1
  fi

  lint_ok "global-check"
}

# When executed directly (not sourced), run with provided arguments.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  global_check_run "$@"
fi
