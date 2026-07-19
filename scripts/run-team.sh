#!/bin/bash
# Team orchestration script
# Reads team-config.yaml and runs agents based on config
# No hardcoded agent names, roles, or commands

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/logging.sh"

AGENT_DIR="$(cd "$SCRIPT_DIR/../agent" && pwd)"
CONFIG="$AGENT_DIR/team-config.yaml"

# Find shared rules (symlink or actual path)
SHARED_DIR="$(cd "$SCRIPT_DIR/../shared" 2>/dev/null && pwd || echo "$SCRIPT_DIR/../shared")"
if [ -L "$SCRIPT_DIR/../shared" ]; then
    SHARED_DIR="$(readlink -f "$SCRIPT_DIR/../shared")"
fi
SHARED_RULES="$SHARED_DIR/rules"
PROJECT_RULES="$(cd "$SCRIPT_DIR/.." && pwd)/rules"

# Parse YAML with Python (no external dependencies)
yaml_get() {
    python3 -c "
import yaml, sys
with open('$CONFIG') as f:
    data = yaml.safe_load(f)
keys = '$1'.split('.')
result = data
for k in keys:
    if result and isinstance(result, dict):
        result = result.get(k)
if result is None:
    sys.exit(1)
if isinstance(result, list):
    for item in result:
        print(item)
elif isinstance(result, dict):
    for k, v in result.items():
        print(f'{k}: {v}')
else:
    print(result)
" 2>/dev/null
}

# Get agent for a role
get_agent_for_role() {
    local role="$1"
    python3 -c "
import yaml
with open('$CONFIG') as f:
    data = yaml.safe_load(f)
agents = data.get('agents', {})
for agent, config in agents.items():
    if role in config.get('roles', []):
        print(agent)
        break
" 2>/dev/null
}

# Get all roles for an agent
get_roles_for_agent() {
    local agent="$1"
    python3 -c "
import yaml
with open('$CONFIG') as f:
    data = yaml.safe_load(f)
agent_config = data.get('agents', {}).get('$agent', {})
roles = agent_config.get('roles', [])
for r in roles:
    print(r)
" 2>/dev/null
}

# Get contract file for a role
get_contract_for_role() {
    local role="$1"
    local contract_file="$AGENT_DIR/${role}.md"
    if [ -f "$contract_file" ]; then
        echo "$contract_file"
    else
        echo ""
    fi
}

# Get gate checklist
get_gate_checklist() {
    local gate_name="$1"
    python3 -c "
import yaml
with open('$CONFIG') as f:
    data = yaml.safe_load(f)
gates = data.get('gates', [])
for gate in gates:
    if gate.get('name') == '$gate_name':
        for item in gate.get('checklist', []):
            print(f'  - [ ] {item}')
        break
" 2>/dev/null
}

# Get workflow gates in order
get_workflow_gates() {
    python3 -c "
import yaml
with open('$CONFIG') as f:
    data = yaml.safe_load(f)
gates = data.get('gates', [])
for gate in gates:
    name = gate.get('name', '')
    from_role = gate.get('from', '')
    to_role = gate.get('to', '')
    print(f'{name}|{from_role}|{to_role}')
" 2>/dev/null
}

# Find agent command (checks common locations)
find_agent_command() {
    local agent_name="$1"
    # Check if command exists in PATH
    if command -v "$agent_name" &> /dev/null; then
        echo "$agent_name"
        return 0
    fi
    # Check common locations
    local locations=(
        "$HOME/.${agent_name}/bin/${agent_name}"
        "$HOME/.local/bin/${agent_name}"
        "/usr/local/bin/${agent_name}"
    )
    for loc in "${locations[@]}"; do
        if [ -x "$loc" ]; then
            echo "$loc"
            return 0
        fi
    done
    return 1
}

# Run agent with role
run_agent() {
    local agent="$1"
    local role="$2"
    local action="$3"
    local task="$4"

    local agent_cmd
    agent_cmd=$(find_agent_command "$agent")

    if [ -z "$agent_cmd" ]; then
        log_error "Agent '$agent' not found in PATH"
        return 1
    fi

    local contract
    contract=$(get_contract_for_role "$role")

    log_agent_start "$agent" "$role" "$action" "$task"
    log_info "agent_cmd=${agent_cmd} contract=${contract:-none}"

    # Execute agent
    local exit_code=0
    "$agent_cmd" --role "$role" --contract "$contract" --action "$action" --task "$task" || exit_code=$?

    log_agent_done "$agent" "$role" "$exit_code"
    return "$exit_code"
}

# Show team status
show_status() {
    log_info "Team Status"
    echo ""

    local team_name
    team_name=$(yaml_get "team.name")
    log_info "team=${team_name}"
    echo ""

    log_info "Agents:"
    python3 -c "
import yaml
with open('$CONFIG') as f:
    data = yaml.safe_load(f)
agents = data.get('agents', {})
for agent, config in agents.items():
    roles = config.get('roles', [])
    desc = config.get('description', '')
    cmd = 'unknown'
    import shutil
    found = shutil.which(agent)
    if found:
        cmd = found
    print(f'  {agent}:')
    print(f'    Command: {cmd}')
    print(f'    Roles: {\", \".join(roles)}')
    print(f'    Description: {desc}')
    print()
" 2>/dev/null

    log_info "Workflow Gates:"
    while IFS='|' read -r name from_role to_role; do
        echo "  $name: $from_role -> $to_role"
    done <<< "$(get_workflow_gates)"
    echo ""

    log_info "branch=$(git branch --show-current 2>/dev/null || echo 'unknown')"
    log_info "last_commit=$(git log --oneline -1 2>/dev/null || echo 'none')"
    log_info "shared_rules=${SHARED_RULES}"
    log_info "project_rules=${PROJECT_RULES}"
}

# Run workflow gate
run_gate() {
    local gate_name="$1"
    local task="$2"

    local gate_info
    gate_info=$(python3 -c "
import yaml
with open('$CONFIG') as f:
    data = yaml.safe_load(f)
gates = data.get('gates', [])
for gate in gates:
    if gate.get('name') == '$gate_name':
        print(f\"{gate.get('from', '')}|{gate.get('to', '')}|{gate.get('name', '')}\")
        break
" 2>/dev/null)

    if [ -z "$gate_info" ]; then
        log_error "Gate '$gate_name' not found in config"
        return 1
    fi

    IFS='|' read -r from_role to_role name <<< "$gate_info"

    local from_agent
    from_agent=$(get_agent_for_role "$from_role")

    if [ -z "$from_agent" ]; then
        log_error "No agent assigned to role '$from_role'"
        return 1
    fi

    log_gate_start "$gate_name" "$from_role" "$to_role" "$task"

    # Get checklist
    local checklist
    checklist=$(get_gate_checklist "$gate_name")
    if [ -n "$checklist" ]; then
        log_debug "gate_checklist=${checklist}"
    fi

    # Determine action based on gate
    local action
    case "$gate_name" in
        design_approval) action="design" ;;
        implementation_complete) action="implement" ;;
        code_review) action="review" ;;
        release_verification) action="verify" ;;
        release) action="release" ;;
        *) action="execute" ;;
    esac

    run_agent "$from_agent" "$from_role" "$action" "$task"
    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        log_gate_done "$gate_name" "success"
        # Log handoff to next role
        local to_agent
        to_agent=$(get_agent_for_role "$to_role")
        if [ -n "$to_agent" ] && [ "$to_role" != "none" ]; then
            log_handoff "$from_agent" "$to_agent" "$task"
        fi
    else
        log_gate_done "$gate_name" "failed"
    fi

    return "$exit_code"
}

# Show usage
show_help() {
    echo "Usage: $(basename "$0") <command> [args...]"
    echo ""
    echo "Commands:"
    echo "  status              Show team status and configuration"
    echo "  gate <gate> <task>  Run a specific workflow gate"
    echo "  workflow <task>     Run full workflow (all gates in order)"
    echo "  agent <name> <role> <action> <task>  Run specific agent"
    echo "  roles               List all roles and assigned agents"
    echo "  gates               List all workflow gates"
    echo "  loop <task>         Run continuous loop (non-stop)"
    echo "  watch               Watch for new tasks in kanban"
    echo "  extract             Extract tasks from docs/"
    echo "  help                Show this help"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") status"
    echo "  $(basename "$0") gate design_approval 'fix token budget'"
    echo "  $(basename "$0") workflow 'fix token budget'"
    echo "  $(basename "$0") agent mimo tech-lead design 'fix token budget'"
    echo "  $(basename "$0") loop 'fix token budget'"
    echo "  $(basename "$0") watch"
    echo "  $(basename "$0") extract"
    echo ""
    echo "Gates (in order):"
    while IFS='|' read -r name from_role to_role; do
        echo "  $name: $from_role → $to_role"
    done <<< "$(get_workflow_gates)"
}

# Run continuous loop
run_loop() {
    local task="$1"
    local interval="${2:-30}"

    log_info "Starting continuous loop for: ${task}"
    log_info "interval=${interval}s"
    log_info "Press Ctrl+C to stop"

    while true; do
        local now
        now=$(date '+%Y-%m-%dT%H:%M:%SZ')
        log_debug "Checking for work..."

        # Check kanban for new tasks
        local kanban="$PROJECT_DIR/.nasim/tasks/kanban.md"
        if [ -f "$kanban" ]; then
            local new_tasks
            new_tasks=$(grep -c "| OPEN |" "$kanban" 2>/dev/null || echo "0")
            if [ "$new_tasks" -gt 0 ]; then
                log_info "Found ${new_tasks} open tasks"
                # Process first open task
                local first_task
                first_task=$(grep "| OPEN |" "$kanban" | head -1 | awk -F'|' '{print $3}' | xargs)
                if [ -n "$first_task" ]; then
                    log_info "Processing: ${first_task}"
                    run_workflow "$first_task"
                fi
            fi
        fi

        # Check for git changes
        local changes
        changes=$(git status --porcelain 2>/dev/null | wc -l)
        if [ "$changes" -gt 0 ]; then
            log_debug "Found ${changes} uncommitted changes"
        fi

        sleep "$interval"
    done
}

# Watch for kanban changes
watch_kanban() {
    local kanban="$PROJECT_DIR/.nasim/tasks/kanban.md"

    log_info "Watching kanban for changes..."
    log_info "Press Ctrl+C to stop"

    if [ ! -f "$kanban" ]; then
        log_error "Kanban not found: ${kanban}"
        exit 1
    fi

    # Use inotifywait if available, otherwise poll
    if command -v inotifywait &> /dev/null; then
        inotifywait -m -e modify "$kanban" | while read -r _; do
            log_debug "Kanban changed, checking for work..."

            # Check for new tasks
            local new_tasks
            new_tasks=$(grep -c "| OPEN |" "$kanban" 2>/dev/null || echo "0")
            if [ "$new_tasks" -gt 0 ]; then
                log_info "Found ${new_tasks} open tasks"
            fi
        done
    else
        # Fallback to polling
        local last_modified=""
        while true; do
            local current_modified
            current_modified=$(stat -c %Y "$kanban" 2>/dev/null || stat -f %m "$kanban" 2>/dev/null)
            if [ "$current_modified" != "$last_modified" ]; then
                log_debug "Kanban changed"
                last_modified="$current_modified"
            fi
            sleep 5
        done
    fi
}

# Parse command
COMMAND="${1:-help}"

case "$COMMAND" in
  help|usage|-h|--help)
    show_help
    ;;

  status)
    show_status
    ;;

  gate)
    GATE="${2:-}"
    TASK="${3:-}"
    if [ -z "$GATE" ] || [ -z "$TASK" ]; then
      log_error "Usage: $(basename "$0") gate <gate-name> <task-description>"
      echo ""
      echo "Available gates:"
      while IFS='|' read -r name from_role to_role; do
        echo "  $name"
      done <<< "$(get_workflow_gates)"
      exit 1
    fi
    run_gate "$GATE" "$TASK"
    ;;

  workflow)
    TASK="${2:-}"
    if [ -z "$TASK" ]; then
      log_error "Usage: $(basename "$0") workflow <task-description>"
      exit 1
    fi

    log_workflow_start "$TASK"

    while IFS='|' read -r name from_role to_role; do
      run_gate "$name" "$TASK" || true
      echo ""
    done <<< "$(get_workflow_gates)"

    log_workflow_done "$TASK" "complete"
    ;;

  agent)
    AGENT="${2:-}"
    ROLE="${3:-}"
    ACTION="${4:-}"
    TASK="${5:-}"
    if [ -z "$AGENT" ] || [ -z "$ROLE" ] || [ -z "$ACTION" ] || [ -z "$TASK" ]; then
      log_error "Usage: $(basename "$0") agent <agent-name> <role> <action> <task>"
      echo ""
      echo "Available agents:"
      python3 -c "
import yaml
with open('$CONFIG') as f:
    data = yaml.safe_load(f)
for agent, config in data.get('agents', {}).items():
    print(f'  {agent}: {\", \".join(config.get(\"roles\", []))}')
" 2>/dev/null
      exit 1
    fi
    run_agent "$AGENT" "$ROLE" "$ACTION" "$TASK"
    ;;

  roles)
    info "Roles and Assignments:"
    echo ""
    python3 -c "
import yaml
with open('$CONFIG') as f:
    data = yaml.safe_load(f)
roles = data.get('roles', {})
agents = data.get('agents', {})
# Build reverse mapping
role_agents = {}
for agent, config in agents.items():
    for role in config.get('roles', []):
        role_agents.setdefault(role, []).append(agent)
for role, config in roles.items():
    assigned = role_agents.get(role, ['unassigned'])
    print(f'{role}:')
    print(f'  Description: {config.get(\"description\", \"\")}')
    print(f'  Assigned to: {\", \".join(assigned)}')
    print()
" 2>/dev/null
    ;;

  gates)
    info "Workflow Gates:"
    echo ""
    while IFS='|' read -r name from_role to_role; do
      echo "  $name: $from_role → $to_role"
    done <<< "$(get_workflow_gates)"
    ;;

  loop)
    TASK="${2:-}"
    INTERVAL="${3:-30}"
    if [ -z "$TASK" ]; then
      log_error "Usage: $(basename "$0") loop <task-description> [interval-seconds]"
      exit 1
    fi
    run_loop "$TASK" "$INTERVAL"
    ;;

  watch)
    watch_kanban
    ;;

  extract)
    "$SCRIPT_DIR/extract-tasks.sh"
    ;;

  *)
    log_error "Unknown command: ${COMMAND}"
    echo "Run $(basename "$0") help for usage"
    exit 1
    ;;
esac
