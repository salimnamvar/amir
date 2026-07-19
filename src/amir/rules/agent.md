# Agent Rules

## Agent Contract Requirements

Every agent MUST follow these rules:

### 1. Role Compliance

- Agent MUST NOT exceed its assigned role
- Agent MUST follow its role contract (in `.nasim/agent/<role>.md`)
- Agent MUST NOT modify files outside its responsibility

### 2. Gate Rules

- Agent MUST NOT skip workflow gates
- Agent MUST complete checklist before passing gate
- Agent MUST wait for previous gate to complete

### 3. Verification Rules

- Coder MUST run unit tests before marking complete
- Coder MUST run integration tests before marking complete
- Coder MUST run CLI smoke tests before marking complete
- QA Engineer MUST verify output content
- Tech Lead MUST run CLI end-to-end before approving

### 4. Communication Rules

- Agent MUST use task-handoff.md template
- Agent MUST report status honestly
- Agent MUST escalate blockers immediately

### 5. Forbidden Behaviors

- Tech Lead MUST NOT code
- Coder MUST NOT decide architecture
- QA Engineer MUST NOT fix bugs
- DevOps MUST NOT skip CI checks
- No agent may replace another role
