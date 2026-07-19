#!/usr/bin/env bash
# a_ prefix argument checker — enforce a_ prefix on all function/method arguments.
#
# Exemptions: self, cls, *args, **kwargs, and anything already starting with a_.
#
# Uses awk for reliable multiline function signature parsing.

if [[ -n "${SETUP_LINT_A_PREFIX_SH:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
SETUP_LINT_A_PREFIX_SH=1

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

_A_PREFIX_AWK='
BEGIN { in_func = 0; paren_depth = 0; buf = ""; raw_buf = ""; func_line = 0; func_name = ""; }

# Detect function / async function definition at start of line (with optional decorators above).
/^[[:space:]]*(async[[:space:]]+)?def[[:space:]]+/ {
    in_func = 1
    paren_depth = 0
    buf = ""
    func_line = NR
    # Extract function name for dunder detection
    line = $0
    sub(/^[[:space:]]*(async[[:space:]]+)?def[[:space:]]+/, "", line)
    sub(/[[:space:]]*\(.*$/, "", line)
    func_name = line
    # fall through to accumulate
}

# Accumulate while inside a function signature (balancing parentheses).
in_func {
    raw_buf = raw_buf $0 "\n"
    # Strip inline comments before accumulating for arg parsing
    line = $0
    sub(/#.*/, "", line)
    buf = buf line
    n = gsub(/\(/, "(", buf)
    # recount on the full buffer
    paren_depth = 0
    for (i = 1; i <= length(buf); i++) {
        c = substr(buf, i, 1)
        if (c == "(") paren_depth++
        if (c == ")") paren_depth--
    }
    if (paren_depth <= 0 && buf != "") {
        # Skip if the function signature contains an a-prefix-ignore marker
        if (index(raw_buf, "a-prefix-ignore") > 0) {
            in_func = 0; buf = ""; raw_buf = ""
            next
        }
        # Skip dunder methods — their signatures are Python protocol requirements
        if (func_name ~ /^__.*__$/) {
            in_func = 0; buf = ""; raw_buf = ""
            next
        }
        # Extract the argument list between the first parens.
        idx = index(buf, "(")
        if (idx > 0) {
            rest = substr(buf, idx + 1)
            # Find matching close paren
            depth = 1
            end = 0
            for (i = 1; i <= length(rest); i++) {
                c = substr(rest, i, 1)
                if (c == "(") depth++
                if (c == ")") { depth--; if (depth == 0) { end = i; break } }
            }
            if (end > 0) {
                argstr = substr(rest, 1, end - 1)
                # Split on commas (outside nested parens/brackets)
                n_args = split_args(argstr, args)
                for (a = 1; a <= n_args; a++) {
                    arg = args[a]
                    # Strip whitespace
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", arg)
                    # Skip empty
                    if (arg == "") continue
                    # Skip * and ** only args
                    if (arg == "*" || arg == "**") continue
                    # Remove leading * or ** for name extraction
                    name = arg
                    gsub(/^\*+/, "", name)
                    # Remove type annotation (after colon or equals)
                    gsub(/:.*/, "", name)
                    gsub(/=.*/, "", name)
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
                    # Skip self, cls, args, kwargs
                    if (name == "self" || name == "cls" || name == "args" || name == "kwargs") continue
                    # Skip if already starts with a_ or _a_ (unused + a-prefix)
                    if (name ~ /^a_/ || name ~ /^_a_/) continue
                    # Skip empty after stripping
                    if (name == "") continue
                    printf "%d:0: error: argument %c%s%c must start with %ca_%c (a-prefix-arg)\n", func_line, 39, name, 39, 39, 39
                    violations++
                }
            }
        }
        in_func = 0
        buf = ""
        raw_buf = ""
    }
}

# split_args: split argstr on commas respecting nested parens/brackets/braces.
function split_args(str,    out, n, depth, i, c, current) {
    n = 0
    depth = 0
    current = ""
    for (i = 1; i <= length(str); i++) {
        c = substr(str, i, 1)
        if (c == "(" || c == "[" || c == "{") depth++
        if (c == ")" || c == "]" || c == "}") depth--
        if (c == "," && depth == 0) {
            n++
            out[n] = current
            current = ""
        } else {
            current = current c
        }
    }
    n++
    out[n] = current
    return n
}

END { exit (violations > 0) ? 1 : 0 }
'

a_prefix_check_run() {
  local dirs=("$@")

  if [[ ${#dirs[@]} -eq 0 ]]; then
    lint_warn "a-prefix-check: no directories provided, skipping"
    return 0
  fi

  lint_step "a_ prefix argument check ${dirs[*]}"

  local py_files=()
  local d
  for d in "${dirs[@]}"; do
    while IFS= read -r -d '' f; do
      py_files+=("$f")
    done < <(find "${d}" -name "*.py" -type f -print0 2>/dev/null)
  done

  if [[ ${#py_files[@]} -eq 0 ]]; then
    lint_warn "a-prefix-check: no .py files found"
    return 0
  fi

  local has_violations=0
  local f
  for f in "${py_files[@]}"; do
    local output
    output=$(awk "${_A_PREFIX_AWK}" "${f}" 2>/dev/null) || true
    if [[ -n "${output}" ]]; then
      while IFS= read -r line; do
        printf "%s:%s\n" "${f}" "${line}"
      done <<< "${output}"
      has_violations=1
    fi
  done

  if [[ "${has_violations}" -eq 1 ]]; then
    lint_fail "a-prefix-arg: violations found"
    return 1
  fi

  lint_ok "a-prefix-arg"
}

# When executed directly (not sourced), run with provided arguments.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  a_prefix_check_run "$@"
fi
