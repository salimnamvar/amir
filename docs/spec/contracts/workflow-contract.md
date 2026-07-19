# Workflow Contract

## Purpose

The Workflow Contract defines a multi-step process with explicit state transitions, task dependencies, human approval gates, and failure handling. Workflows are the top-level orchestration constructs that coordinate multiple tasks into a cohesive process.

## Schema

```yaml
WorkflowContract:
  type: workflow-contract
  version: string (semantic version)
  workflow:
    id: string (UUID)
    name: string
    description: string
    template: boolean (true if this is a reusable template)
  states:
    - name: string (unique state identifier)
      type: enum [task, approval, parallel, conditional]
      description: string
      entry_action: string (optional, action to run on entry)
      exit_action: string (optional, action to run on exit)
  transitions:
    - from_state: string
      to_state: string
      condition: string (optional expression)
      guard: string (optional policy reference)
  tasks:
    - task_template: string (reference to TaskContract)
      state: string (which state this task belongs to)
      dependencies:
        - task_id: string
          type: enum [hard, soft]
      parallel_group: string (optional, for parallel execution)
  approval_gates:
    - gate_id: string
      state: string
      approvers:
        - role: string
        - user: string (optional)
      timeout: duration (optional)
      on_timeout: enum [reject, approve, escalate]
      quorum: int (optional, default: 1)
  failure_handling:
    - state: string
      on_failure: enum [retry, compensate, escalate, abort]
      compensation_workflow: string (optional reference)
      retry_policy:
        max_attempts: int
        backoff: duration
  resource_requirements:
    - resource: string (e.g., "concurrent_tasks")
      limit: int
  metadata:
    created_at: timestamp
    updated_at: timestamp
    owner: string
```

## Invariants

1. **State Completeness**: All referenced states in transitions must exist
2. **Task State Binding**: Every task must belong to exactly one state
3. **Approval Quorum**: Quorum count must not exceed approver count
4. **DAG Closure**: Task dependencies must form a valid DAG
5. **Failure Coverage**: Every non-terminal state must have failure handling

## Lifecycle

| State | Description |
|-------|-------------|
| Draft | Workflow definition being created |
| Testing | Workflow being validated in sandbox |
| Published | Available for instantiation |
| Deprecated | Superseded by newer version |

## Validation Rules

### Structure Validation
1. **State Machine Validity**: Transitions must not create cycles
2. **Task Reference Integrity**: All task references must resolve
3. **Approval Gate Validity**: Approvers must have valid role references

### Behavioral Validation
1. **Path Coverage**: All execution paths must be testable
2. **Failure Scenarios**: Every state must handle failures
3. **Resource Bounds**: Resource requirements must be feasible

## Examples

### Software Delivery Workflow

```yaml
type: workflow-contract
version: "1.0.0"
workflow:
  id: "wf-delivery-001"
  name: "software-delivery"
  description: "Standard software development lifecycle workflow"
  template: true
states:
  - name: REQUESTED
    type: task
    description: "Task received and queued"
    
  - name: PLANNED
    type: task
    description: "Architecture and planning completed"
    
  - name: ARCHITECTURE_REVIEW
    type: approval
    description: "Waiting for architecture sign-off"
    
  - name: IMPLEMENTATION
    type: parallel
    description: "Code implementation and testing"
    
  - name: TESTING
    type: task
    description: "Test execution and validation"
    
  - name: REVIEW
    type: approval
    description: "Peer review of changes"
    
  - name: COMMITTED
    type: task
    description: "Changes committed to repository"
    
  - name: COMPLETED
    type: task
    description: "Workflow successfully finished"
    
  - name: FAILED
    type: task
    description: "Workflow failed irrecoverably"
    
  - name: BLOCKED
    type: task
    description: "Workflow waiting for intervention"
transitions:
  - from_state: REQUESTED
    to_state: PLANNED
    
  - from_state: PLANNED
    to_state: ARCHITECTURE_REVIEW
    guard: "team:size > 1"
    
  - from_state: ARCHITECTURE_REVIEW
    to_state: IMPLEMENTATION
    condition: "approval:status == approved"
    
  - from_state: ARCHITECTURE_REVIEW
    to_state: PLANNED
    condition: "approval:status == rejected"
    
  - from_state: IMPLEMENTATION
    to_state: TESTING
    
  - from_state: TESTING
    to_state: REVIEW
    condition: "tests:passed == true"
    
  - from_state: TESTING
    to_state: IMPLEMENTATION
    condition: "tests:failed == true AND retry:attempts < 3"
    
  - from_state: REVIEW
    to_state: COMMITTED
    condition: "approval:status == approved"
    
  - from_state: REVIEW
    to_state: IMPLEMENTATION
    condition: "approval:status == changes_requested"
    
  - from_state: COMMITTED
    to_state: COMPLETED
    
  - from_state: REQUESTED
    to_state: BLOCKED
    condition: "priority:urgent == false AND time:outside_working_hours == true"
tasks:
  - task_template: "task-planning"
    state: PLANNED
    dependencies: []
    
  - task_template: "task-implement"
    state: IMPLEMENTATION
    dependencies:
      - task_id: "task-planning"
        type: hard
    parallel_group: "development"
    
  - task_template: "task-test"
    state: TESTING
    dependencies:
      - task_id: "task-implement"
        type: hard
        
  - task_template: "task-create-pr"
    state: COMMITTED
    dependencies:
      - task_id: "task-implement"
        type: hard
approval_gates:
  - gate_id: "architecture-approval"
    state: ARCHITECTURE_REVIEW
    approvers:
      - role: architect
    timeout: "48h"
    on_timeout: escalate
    
  - gate_id: "code-review-approval"
    state: REVIEW
    approvers:
      - role: reviewer
      - role: team_lead
    timeout: "24h"
    on_timeout: escalate
    quorum: 1
failure_handling:
  - state: IMPLEMENTATION
    on_failure: retry
    retry_policy:
      max_attempts: 3
      backoff: "30m"
      
  - state: TESTING
    on_failure: retry
    retry_policy:
      max_attempts: 2
      backoff: "15m"
      
  - state: REVIEW
    on_failure: abort
    
  - state: COMMITTED
    on_failure: compensate
    compensation_workflow: "wf-rollback-changes"
resource_requirements:
  - resource: concurrent_tasks
    limit: 5
  - resource: max_parallel_development
    limit: 3
metadata:
  created_at: "2026-07-19T00:00:00Z"
  owner: "platform-engineering"
```

### Hotfix Workflow

```yaml
type: workflow-contract
version: "1.0.0"
workflow:
  id: "wf-hotfix-001"
  name: "hotfix"
  description: "Accelerated workflow for critical fixes"
  template: true
states:
  - name: REQUESTED
    type: task
  - name: IMPLEMENTATION
    type: task
  - name: QUICK_TEST
    type: task
  - name: AUTO_APPROVE
    type: approval
  - name: COMMITTED
    type: task
transitions:
  # Simplified transitions with auto-approval for hotfixes
  - from_state: REQUESTED
    to_state: IMPLEMENTATION
    
  - from_state: IMPLEMENTATION
    to_state: QUICK_TEST
    
  - from_state: QUICK_TEST
    to_state: AUTO_APPROVE
    condition: "tests:passed == true"
    
  - from_state: AUTO_APPROVE
    to_state: COMMITTED
    # Auto-approve after tests pass
    
  - from_state: AUTO_APPROVE
    to_state: IMPLEMENTATION
    condition: "tests:failed == true AND attempts < 2"
approval_gates:
  - gate_id: "auto-approval"
    state: AUTO_APPROVE
    approvers: []  # Empty = auto-approve
    on_timeout: approve
```

## Relationships

- **Task Contract**: Workflow contains task templates
- **Role Contract**: Tasks reference roles
- **Artifact Contract**: Tasks consume and produce artifacts
- **Policy Contract**: Workflows subject to team policies