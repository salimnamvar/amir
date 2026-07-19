#!/bin/bash
# Extract tasks from docs/ directory
# Reads ADRs and RELEASE_NOTES.md to find actionable items

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/logging.sh"

PROJECT_DIR="$(cd "$SCRIPT_DIR/../../" && pwd)"
DOCS_DIR="$PROJECT_DIR/docs"
TASK_DIR="$PROJECT_DIR/.nasim/tasks"
KANBAN="$TASK_DIR/kanban.md"

# Create task directory if needed
mkdir -p "$TASK_DIR"

# Extract tasks from ADRs
extract_adr_tasks() {
    log_info "Extracting tasks from ADRs..."

    for adr in "$DOCS_DIR/architecture"/ADR-*.md; do
        if [ -f "$adr" ]; then
            local adr_name
            adr_name=$(basename "$adr" .md)

            local status
            status=$(grep -i "Status:" "$adr" | head -1 | awk '{print $2}')

            if [ "$status" = "Deferred" ] || [ "$status" = "ACCEPTED" ]; then
                local target
                target=$(grep -i "Target:" "$adr" | head -1 | awk '{print $2}')

                local description
                description=$(head -20 "$adr" | grep -v "^#" | grep -v "^$" | head -5)

                log_info "adr=${adr_name} status=${status} target=${target}"

                # Add to kanban
                local task_id
                task_id=$(grep -c "^| T" "$KANBAN" 2>/dev/null || echo "0")
                task_id=$((task_id + 1))

                echo "| T$task_id | ADR: $adr_name | MEDIUM | OpenCode | OPEN |" >> "$KANBAN"
            fi
        fi
    done
}

# Extract tasks from RELEASE_NOTES
extract_release_tasks() {
    log_info "Extracting tasks from RELEASE_NOTES.md..."

    local release_file="$DOCS_DIR/RELEASE_NOTES.md"

    if [ ! -f "$release_file" ]; then
        log_warning "RELEASE_NOTES.md not found"
        return
    fi

    # Extract Known Limitations
    log_info "Known Limitations:"
    sed -n '/^## Known Limitations/,/^## /p' "$release_file" | grep "^-" | while read -r line; do
        echo "  $line"

        local task_id
        task_id=$(grep -c "^| T" "$KANBAN" 2>/dev/null || echo "0")
        task_id=$((task_id + 1))

        local task_name
        task_name=$(echo "$line" | sed 's/^- //' | cut -d'(' -f1 | xargs)

        echo "| T$task_id | $task_name | MEDIUM | OpenCode | OPEN |" >> "$KANBAN"
    done
    echo ""

    # Extract Technical Debt
    log_info "Technical Debt:"
    sed -n '/^## Technical Debt/,/^## /p' "$release_file" | grep "^-" | while read -r line; do
        echo "  $line"

        local task_id
        task_id=$(grep -c "^| T" "$KANBAN" 2>/dev/null || echo "0")
        task_id=$((task_id + 1))

        local task_name
        task_name=$(echo "$line" | sed 's/^- //' | cut -d':' -f2 | cut -d'(' -f1 | xargs)

        echo "| T$task_id | $task_name | LOW | OpenCode | OPEN |" >> "$KANBAN"
    done
    echo ""

    # Extract Future items
    log_info "Future Items:"
    sed -n '/^## Future/,/^## /p' "$release_file" | grep "^-" | while read -r line; do
        echo "  $line"

        local task_id
        task_id=$(grep -c "^| T" "$KANBAN" 2>/dev/null || echo "0")
        task_id=$((task_id + 1))

        local task_name
        task_name=$(echo "$line" | sed 's/^- //' | xargs)

        echo "| T$task_id | $task_name | LOW | OpenCode | OPEN |" >> "$KANBAN"
    done
    echo ""
}

# Extract tasks from audit document
extract_audit_tasks() {
    log_info "Extracting tasks from audit document..."

    local audit_file="$TASK_DIR/input-scoping-and-output-audit.md"

    if [ ! -f "$audit_file" ]; then
        log_warning "Audit document not found"
        return
    fi

    # Extract issues
    log_info "Issues from audit:"
    grep "^### Issue" "$audit_file" | while read -r line; do
        local issue_name
        issue_name=$(echo "$line" | sed 's/### //' | sed 's/^[0-9]*: //')

        echo "  $issue_name"

        local task_id
        task_id=$(grep -c "^| T" "$KANBAN" 2>/dev/null || echo "0")
        task_id=$((task_id + 1))

        echo "| T$task_id | $issue_name | HIGH | OpenCode | OPEN |" >> "$KANBAN"
    done
    echo ""
}

# Update kanban header
update_kanban_header() {
    local kanban="$1"
    local temp_file
    temp_file=$(mktemp)

    # Keep header, update timestamp
    head -7 "$kanban" > "$temp_file"
    echo "**Last updated:** $(date '+%Y-%m-%d')" >> "$temp_file"
    echo "" >> "$temp_file"

    # Add rest of file (skip old header)
    tail -n +8 "$kanban" >> "$temp_file"

    mv "$temp_file" "$kanban"
}

# Main extraction
main() {
    log_info "Starting task extraction from docs/"

    # Initialize kanban if needed
    if [ ! -f "$KANBAN" ]; then
        cat > "$KANBAN" << 'EOF'
# Task Kanban Board

**Last updated:** $(date '+%Y-%m-%d')

---

## BACKLOG

| ID | Task | Priority | Assigned | Status |
|----|------|----------|----------|--------|
EOF
    fi

    # Extract tasks
    extract_adr_tasks
    extract_release_tasks
    extract_audit_tasks

    # Update timestamp
    update_kanban_header "$KANBAN"

    log_info "Task extraction complete"
    log_info "kanban=${KANBAN} total_tasks=$(grep -c "^| T" "$KANBAN" 2>/dev/null || echo "0")"
}

# Run
main
