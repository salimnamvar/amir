# Team Contract

## Purpose

The Team Contract defines a team's structure, including role assignments, policies, and operational constraints. It binds abstract role definitions to concrete agent implementations and establishes the governance boundary for collaborative work.

## Schema

```yaml
TeamContract:
  type: team-contract
  version: string (semantic version)
  team:
    id: string (UUID)
    name: string
    description: string
  role_bindings:
    - role_name: string (reference to RoleContract)
      agent_binding: string (reference to AgentContract or adapter name)
      agent_version: string (version constraint, e.g., ">=1.0.0")
      capabilities:
        - skill: string
          minimum_proficiency: enum [novice, intermediate, expert]
      weight: int (for load balancing, optional)
  policies:
    - policy_name: string (reference to PolicyContract)
      parameters: {key: value}
  budget:
    daily_usd_limit: decimal
    monthly_token_limit: int
    per_task_max_usd: decimal
  environment:
    repositories: [string]
    variables: {key: value}
    secrets: [secret_reference]
  constraints:
    max_concurrent_tasks: int
    working_hours_only: boolean
  metadata:
    created_at: timestamp
    updated_at: timestamp
    owner: string
```

## Invariants

1. **Unique Role Names**: Each role name within a team must be unique
2. **Agent Availability**: Bound agents must be registered and healthy
3. **Capability Coverage**: All required capabilities for workflows must be covered
4. **Budget Constraints**: Budget limits must be positive numbers
5. **Security Alignment**: Team policies must not conflict with global security rules

## Lifecycle

| State | Description |
|-------|-------------|
| Draft | Team structure being defined |
| Active | Team available for task assignment |
| Suspended | Temporarily inactive |
| Archived | No longer accepting new tasks |

## Validation Rules

1. **Agent Resolution**: All agent bindings must resolve to active agent registrations
2. **Capability Coverage**: Required capabilities for team workflows must be available
3. **Budget Validation**: Budget limits must be within tenant/project constraints
4. **Policy Consistency**: Team policies must not conflict with each other

## Examples

### Software Engineering Team

```yaml
type: team-contract
version: "1.0.0"
team:
  id: "team-eng-001"
  name: "software-engineering"
  description: "Full-stack development team for core services"
role_bindings:
  - role_name: architect
    agent_binding: claude-code
    agent_version: ">=1.2.0"
    capabilities:
      - skill: architecture_analysis
        minimum_proficiency: expert
    weight: 1
    
  - role_name: developer
    agent_binding: codex
    agent_version: ">=1.0.0"
    capabilities:
      - skill: refactoring
        minimum_proficiency: intermediate
      - skill: code_generation
        minimum_proficiency: expert
    weight: 3
    
  - role_name: reviewer
    agent_binding: opencode
    agent_version: ">=1.0.0"
    capabilities:
      - skill: code_review
        minimum_proficiency: expert
    weight: 2
policies:
  - policy_name: branch_protection
    parameters:
      protected_branches: ["main", "production"]
      required_approvals: 1
  - policy_name: cost_limit_daily
    parameters:
      max_usd: 50.00
  - policy_name: working_hours
    parameters:
      timezone: "UTC"
      start_hour: 9
      end_hour: 18
budget:
  daily_usd_limit: 100.00
  monthly_token_limit: 10000000
  per_task_max_usd: 10.00
environment:
  repositories:
    - "github.com/org/repo"
  variables:
    PYTHON_VERSION: "3.11"
    NODE_VERSION: "20.x"
constraints:
  max_concurrent_tasks: 10
metadata:
  created_at: "2026-07-19T00:00:00Z"
  owner: "platform-engineering"
```

### Security Review Team

```yaml
type: team-contract
version: "1.0.0"
team:
  id: "team-sec-001"
  name: "security-review"
  description: "Specialized team for security analysis"
role_bindings:
  - role_name: security_analyst
    agent_binding: claude-code
    capabilities:
      - skill: security_review
        minimum_proficiency: expert
policies:
  - policy_name: secrets_redaction
    parameters:
      enabled: true
  - policy_name: compliance_check
    parameters:
      standards: ["SOC2", "ISO27001"]
budget:
  daily_usd_limit: 50.00
  monthly_token_limit: 5000000
constraints:
  max_concurrent_tasks: 5
```

## Relationships

- **Role Contract**: Team binds role definitions to agent implementations
- **Agent Contract**: Agent binding references registered agent
- **Policy Contract**: Team policies constrain role behavior
- **Workflow Contract**: Team defines scope for workflow execution