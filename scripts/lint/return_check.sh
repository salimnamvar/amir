#!/usr/bin/env bash
# return_check.sh — Enforce single return per function.
#
# Rule: Every function/method must have exactly ONE return statement.
# No early returns, no guard clauses, no exceptions.
#
# Uses awk to track function boundaries and count return statements.

if [[ -n "${SETUP_LINT_RETURN_CHECK_SH:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
SETUP_LINT_RETURN_CHECK_SH=1

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

_RETURN_CHECK_AWK='
BEGIN {
    in_func = 0
    func_indent = 0
    func_line = 0
    func_name = ""
    return_count = 0
    paren_depth = 0
    buf = ""
    violations = 0
}

# Detect function/method definition
/^[[:space:]]*(async[[:space:]]+)?def[[:space:]]+/ {
    # If we were in a function, check its return count
    if (in_func && return_count > 1) {
        printf "%d:0: error: function \"%s\" has %d return statements (single-return)\n", func_line, func_name, return_count
        violations++
    }

    # Start tracking new function
    in_func = 1
    line = $0
    gsub(/[^[:space:]].*$/, "", line)
    func_indent = length(line)
    func_line = NR

    # Extract function name
    fname = $0
    sub(/^[[:space:]]*(async[[:space:]]+)?def[[:space:]]+/, "", fname)
    sub(/[[:space:]]*\(.*$/, "", fname)
    func_name = fname

    # Reset return count and paren tracking
    return_count = 0
    paren_depth = 0
    buf = ""
    next
}

# Track parentheses for multi-line signatures
in_func {
    # Accumulate for paren balancing
    line = $0
    sub(/#.*/, "", line)  # strip comments
    buf = buf line

    # Count parens
    for (i = 1; i <= length(line); i++) {
        c = substr(line, i, 1)
        if (c == "(") paren_depth++
        if (c == ")") paren_depth--
    }

    # Only count returns after signature is complete (parens balanced or never opened)
    if (paren_depth <= 0) {
        # Check for return statement (not in comments/strings)
        check_line = $0
        gsub(/#.*/, "", check_line)  # remove comments
        gsub(/"[^"]*"/, "", check_line)  # remove double-quoted strings
        gsub(/\047[^\047]*\047/, "", check_line)  # remove single-quoted strings

        if (check_line ~ /^[[:space:]]*return[[:space:]]/ ||
            check_line ~ /^[[:space:]]*return$/) {
            return_count++
        }
    }
}

# Handle end of file — check last function
END {
    if (in_func && return_count > 1) {
        printf "%d:0: error: function \"%s\" has %d return statements (single-return)\n", func_line, func_name, return_count
        violations++
    }
    exit (violations > 0) ? 1 : 0
}
'

return_check_run() {
  local dirs=("$@")

  if [[ ${#dirs[@]} -eq 0 ]]; then
    lint_warn "return-check: no directories provided, skipping"
    return 0
  fi

  lint_step "single-return check ${dirs[*]}"

  local py_files=()
  local d
  for d in "${dirs[@]}"; do
    while IFS= read -r -d '' f; do
      py_files+=("$f")
    done < <(find "${d}" -name "*.py" -type f -print0 2>/dev/null)
  done

  if [[ ${#py_files[@]} -eq 0 ]]; then
    lint_warn "return-check: no .py files found"
    return 0
  fi

  local has_violations=0
  local f
  for f in "${py_files[@]}"; do
    local output
    output=$(awk "${_RETURN_CHECK_AWK}" "${f}" 2>/dev/null) || true
    if [[ -n "${output}" ]]; then
      while IFS= read -r line; do
        printf "%s:%s\n" "${f}" "${line}"
      done <<< "${output}"
      has_violations=1
    fi
  done

  if [[ "${has_violations}" -eq 1 ]]; then
    lint_fail "return-check: multiple return statements found"
    return 1
  fi

  lint_ok "return-check"
}

# When executed directly (not sourced), run with provided arguments.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  return_check_run "$@"
fi
