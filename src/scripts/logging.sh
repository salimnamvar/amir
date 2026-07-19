#!/bin/bash
# Centralized async logging library for NASIM agents.
#
# Mirrors the formatting policy from src/arian/bootstrap/logging.py:
#   Diagnostic (< INFO):  LEVEL WHEN WHERE RESOURCE : MESSAGE
#   Operational (>= INFO): LEVEL WHEN RESOURCE : MESSAGE
#
# Architecture:
#   log_*() writes lines to a background listener via file descriptor.
#   The listener reads from the FD and writes to rotating log files.
#   No blocking, no data loss — the listener handles rotation.
#
# Usage:
#   source "$(dirname "$0")/logging.sh"
#   log_info "Starting workflow"
#   log_debug "Parsing config" "resource=config.yaml"
#   log_cleanup   # call on script exit to drain and stop listener

# ---------------------------------------------------------------------------
# Configuration (override via environment before sourcing)
# ---------------------------------------------------------------------------
_NASIM_LOG_DIR="${NASIM_LOG_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/log}"
_NASIM_LOG_MAX_BYTES="${NASIM_LOG_MAX_BYTES:-10485760}"   # 10 MB
_NASIM_LOG_BACKUP_COUNT="${NASIM_LOG_BACKUP_COUNT:-5}"
_NASIM_LOG_LEVEL="${NASIM_LOG_LEVEL:-DEBUG}"              # DEBUG|INFO|WARNING|ERROR

# Internal state
_NASIM_LOG_FIFO=""
_NASIM_LOG_LISTENER_PID=""
_NASIM_LOG_INITIALIZED=0
_NASIM_LOG_FD=""

# ---------------------------------------------------------------------------
# Level helpers
# ---------------------------------------------------------------------------
_nasim_level_num() {
    case "${1^^}" in
        DEBUG)    echo 10 ;;
        INFO)     echo 20 ;;
        WARNING)  echo 30 ;;
        ERROR)    echo 40 ;;
        CRITICAL) echo 50 ;;
        *)        echo 20 ;;
    esac
}

_NASIM_CURRENT_LEVEL=$(_nasim_level_num "$_NASIM_LOG_LEVEL")

# ---------------------------------------------------------------------------
# Timestamp — UTC ISO-8601 with microseconds, matching Python logger
# ---------------------------------------------------------------------------
_nasim_utc_timestamp() {
    local ns
    ns=$(date +%s.%N 2>/dev/null || date +%s)
    ns="${ns%%N}"
    local sec frac
    sec="${ns%%.*}"
    frac="${ns#*.}"
    frac="${frac:0:6}"
    while [ ${#frac} -lt 6 ]; do frac="${frac}0"; done
    local iso
    iso=$(date -u -d "@${sec}" '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || date -u -r "${sec}" '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || echo "1970-01-01T00:00:00")
    echo "${iso}.${frac}Z"
}

# ---------------------------------------------------------------------------
# Listener process — reads FIFO, writes to rotating log files
# ---------------------------------------------------------------------------
_nasim_log_listener() {
    local fifo="$1"
    local log_dir="$2"
    local max_bytes="$3"
    local backup_count="$4"
    local main_log="${log_dir}/nasim.log"

    # Open FD 3 for reading from FIFO (blocks until writer opens other end)
    exec 3< "$fifo"

    while IFS= read -r line <&3; do
        [[ "$line" == "__NASIM_LOG_STOP__" ]] && break

        # Rotate if needed
        if [ -f "$main_log" ]; then
            local size
            size=$(stat -c%s "$main_log" 2>/dev/null || stat -f%z "$main_log" 2>/dev/null || echo 0)
            if [ "$size" -ge "$max_bytes" ]; then
                local i=$backup_count
                while [ $i -gt 0 ]; do
                    local prev=$((i - 1))
                    local src="${main_log}$([ $prev -eq 0 ] && echo "" || echo ".${prev}")"
                    local dst="${main_log}.${i}"
                    [ -f "$src" ] && mv "$src" "$dst"
                    i=$((i - 1))
                done
                : > "$main_log"
            fi
        fi

        echo "$line" >> "$main_log"
    done

    exec 3<&-
}

# ---------------------------------------------------------------------------
# Initialize — create FIFO, start listener, register cleanup
# ---------------------------------------------------------------------------
log_init() {
    [ "$_NASIM_LOG_INITIALIZED" -eq 1 ] && return 0

    mkdir -p "$_NASIM_LOG_DIR"

    _NASIM_LOG_FIFO="${_NASIM_LOG_DIR}/.log_fifo_$$"
    mkfifo "$_NASIM_LOG_FIFO"

    # Start listener in background
    _nasim_log_listener "$_NASIM_LOG_FIFO" "$_NASIM_LOG_DIR" \
        "$_NASIM_LOG_MAX_BYTES" "$_NASIM_LOG_BACKUP_COUNT" &
    _NASIM_LOG_LISTENER_PID=$!

    # Open write-end of FIFO on FD 4 (persists across calls, non-blocking)
    exec 4> "$_NASIM_LOG_FIFO"
    _NASIM_LOG_FD=4

    trap log_cleanup EXIT INT TERM HUP
    _NASIM_LOG_INITIALIZED=1
}

# ---------------------------------------------------------------------------
# Cleanup — close FD, send sentinel, stop listener
# ---------------------------------------------------------------------------
log_cleanup() {
    [ "$_NASIM_LOG_INITIALIZED" -eq 0 ] && return 0
    _NASIM_LOG_INITIALIZED=0

    # Close write FD — signals EOF to listener
    exec 4>&- 2>/dev/null || true

    # Wait for listener to drain and exit
    if [ -n "$_NASIM_LOG_LISTENER_PID" ]; then
        local waited=0
        while kill -0 "$_NASIM_LOG_LISTENER_PID" 2>/dev/null && [ $waited -lt 50 ]; do
            sleep 0.1
            waited=$((waited + 1))
        done
        kill "$_NASIM_LOG_LISTENER_PID" 2>/dev/null || true
    fi

    rm -f "$_NASIM_LOG_FIFO" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Core log emitter — writes formatted line to FD 4
# ---------------------------------------------------------------------------
_nasim_log_emit() {
    local level="$1"
    local message="$2"
    local resource="${3:-}"

    log_init

    local level_num
    level_num=$(_nasim_level_num "$level")
    [ "$level_num" -lt "$_NASIM_CURRENT_LEVEL" ] && return 0

    local when
    when="$(_nasim_utc_timestamp)"

    local line
    if [ "$level_num" -lt 20 ]; then
        local where="${BASH_SOURCE[1]:-unknown}:${BASH_LINENO[0]:-0}"
        line="${level} ${when} ${where}${resource:+ ${resource}} : ${message}"
    else
        line="${level} ${when}${resource:+ ${resource}} : ${message}"
    fi

    # Non-blocking write via persistent FD
    printf '%s\n' "$line" >&$_NASIM_LOG_FD 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Public API — matches Python logger method names
# ---------------------------------------------------------------------------
log_debug()   { _nasim_log_emit "DEBUG"   "$1" "${2:-}"; }
log_info()    { _nasim_log_emit "INFO"    "$1" "${2:-}"; }
log_warning() { _nasim_log_emit "WARNING" "$1" "${2:-}"; }
log_error()   { _nasim_log_emit "ERROR"   "$1" "${2:-}"; }
log_critical(){ _nasim_log_emit "CRITICAL" "$1" "${2:-}"; }

# Convenience aliases
log()   { log_info "$1" "${2:-}"; }
warn()  { log_warning "$1" "${2:-}"; }
error() { log_error "$1" "${2:-}"; }
info()  { log_info "$1" "${2:-}"; }

# ---------------------------------------------------------------------------
# Agent collaboration logging — structured entries for observing teamwork
# ---------------------------------------------------------------------------
log_agent_start() {
    local agent="$1" role="$2" action="$3" task="$4"
    log_info "AGENT_START agent=${agent} role=${role} action=${action} task=${task}" "resource=agent=${agent}"
}

log_agent_done() {
    local agent="$1" role="$2" exit_code="$3"
    log_info "AGENT_DONE agent=${agent} role=${role} exit_code=${exit_code}" "resource=agent=${agent}"
}

log_gate_start() {
    local gate="$1" from="$2" to="$3" task="$4"
    log_info "GATE_START gate=${gate} from=${from} to=${to} task=${task}" "resource=gate=${gate}"
}

log_gate_done() {
    local gate="$1" status="$2"
    log_info "GATE_DONE gate=${gate} status=${status}" "resource=gate=${gate}"
}

log_handoff() {
    local from_agent="$1" to_agent="$2" task="$3"
    log_info "HANDOFF from=${from_agent} to=${to_agent} task=${task}" "resource=collaboration"
}

log_workflow_start() {
    local task="$1"
    log_info "WORKFLOW_START task=${task}" "resource=workflow"
}

log_workflow_done() {
    local task="$1" status="$2"
    log_info "WORKFLOW_DONE task=${task} status=${status}" "resource=workflow"
}
