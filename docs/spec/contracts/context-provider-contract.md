# Context Provider Contract

## Purpose

The Context Provider Contract defines how external systems integrate with Amir to provide contextual information to agents. Context providers supply repository state, environment variables, documentation, and other data needed for task execution.

Context providers are external systems (like Arian) that supply context to Amir. Amir must not depend on any specific context provider - all integration happens through this contract.

## Schema

```yaml
ContextProviderContract:
  type: context-provider-contract
  version: string (semantic version)
  provider:
    id: string (UUID)
    name: string
    type: enum [repository, documentation, api, database, custom]
    endpoint: string (optional, for API-based providers)
  capabilities:
    - provided_context_type: string (e.g., "RepositoryContext", "APIDocumentation")
      format: enum [json, yaml, markdown, binary]
      refresh_rate_seconds: int
      cacheable: boolean
  authentication:
    method: enum [none, token, oauth, mtls, api_key]
    scope: string (permission scope required)
  security_profile:
    data_access:
      - resource: string
        permissions: [read, write, delete]
    rate_limits:
      - resource: string
        requests_per_minute: int
  schema:
    context_type: string
    properties: {}
    required: []
  health_check:
    endpoint: string (optional)
    interval_seconds: int (default: 60)
  metadata:
    created_at: timestamp
    updated_at: timestamp
```

## Supported Context Types

### RepositoryContext

Provides repository state including files, branches, and history.

```yaml
type: RepositoryContext
repository:
  url: string
  branch: string
  commit_sha: string
  files:
    - path: string
      content: string
      size_bytes: int
      last_modified: timestamp
  structure:
    - path: string
      type: enum [file, directory]
      children: [string]
variables:
  environment: {key: value}
  secrets: [string] (masked references only)
```

### APIDocumentationContext

Provides API documentation and schemas.

```yaml
type: APIDocumentationContext
apis:
  - name: string
    version: string
    spec: string (OpenAPI/AsyncAPI spec)
    endpoints:
      - path: string
        method: enum [GET, POST, PUT, DELETE]
        request_schema: {}
        response_schema: {}
documentation:
  - title: string
    content: string
    url: string (optional)
```

### DatabaseSchemaContext

Provides database schema and sample data.

```yaml
type: DatabaseSchemaContext
database:
  type: string
  connection_info:
    host: string (masked)
    port: int
    database: string
  schema:
    tables:
      - name: string
        columns:
          - name: string
            type: string
            nullable: boolean
            primary_key: boolean
        relationships:
          - table: string
            type: enum [one_to_one, one_to_many, many_to_many]
  sample_data:
    - table: string
      rows:
        - {column: value}
```

## Invariants

1. **Context Freshness**: Context must be refreshed within declared intervals
2. **Security Boundaries**: Providers must respect access control
3. **Rate Limiting**: Requests must be throttled per configured limits
4. **Data Masking**: Secrets must never be exposed in context
5. **Format Compliance**: All context must conform to declared schema

## Lifecycle

| State | Description |
|-------|-------------|
| Registering | Provider being onboarded |
| Active | Provider available for context requests |
| Degraded | Provider experiencing issues but partially available |
| Unavailable | Provider offline or unreachable |
| Retired | Provider no longer used |

## Validation Rules

1. **Schema Validation**: Context must match declared schema
2. **Freshness Check**: Context must be within refresh window
3. **Size Limits**: Context payload must be within size bounds
4. **Security Scan**: No secrets or sensitive data exposed

## Examples

### Git Repository Provider

```yaml
type: context-provider-contract
version: "1.0.0"
provider:
  id: "repo-provider-001"
  name: "git-repository"
  type: repository
capabilities:
  - provided_context_type: RepositoryContext
    format: json
    refresh_rate_seconds: 300
    cacheable: true
authentication:
  method: token
  scope: "repo:read"
security_profile:
  data_access:
    - resource: "repository/*"
      permissions: [read]
  rate_limits:
    - resource: "context_requests"
      requests_per_minute: 100
schema:
  context_type: RepositoryContext
  properties:
    repository:
      type: object
      properties:
        url: {type: string}
        branch: {type: string}
        commit_sha: {type: string}
metadata:
  created_at: "2026-07-19T00:00:00Z"
```

### Custom Documentation Provider

```yaml
type: context-provider-contract
version: "1.0.0"
provider:
  id: "arian-provider-001"
  name: "arian-context"
  type: documentation
  endpoint: "https://arian.example.com/api/v1/context"
capabilities:
  - provided_context_type: DocumentationContext
    format: markdown
    refresh_rate_seconds: 3600
    cacheable: true
authentication:
  method: oauth
  scope: "context:read"
schema:
  context_type: DocumentationContext
  properties:
    documentation:
      type: array
      items:
        type: object
        properties:
          title: {type: string}
          content: {type: string}
```

## Relationships

- **Task Contract**: Tasks declare required context types
- **Workflow Contract**: Workflows specify context requirements
- **Policy Contract**: Context access subject to policies
- **External System**: Providers integrate external data sources

## Integration Patterns

Context providers integrate through:

1. **Pull Model**: Amir requests context on-demand
2. **Push Model**: Provider pushes context updates via webhook
3. **Cache Model**: Provider caches context; Amir refreshes periodically

Context is injected into task execution through:
- Mounted files in sandbox
- Environment variables (masked)
- API endpoints accessible within sandbox
- Inline payload in TaskContract