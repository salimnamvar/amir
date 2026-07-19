"""Domain ID Value Objects."""

from pydantic import BaseModel
from uuid import UUID


class TaskId(BaseModel):
    """Strongly-typed Task identifier."""
    value: UUID


class AgentDefinitionId(BaseModel):
    """Strongly-typed Agent Definition identifier."""
    value: UUID


class WorkflowInstanceId(BaseModel):
    """Strongly-typed Workflow Instance identifier."""
    value: UUID


class ArtifactId(BaseModel):
    """Strongly-typed Artifact identifier."""
    value: UUID


class InvocationId(BaseModel):
    """Strongly-typed Invocation identifier."""
    value: UUID


class ContractId(BaseModel):
    """Strongly-typed Contract identifier."""
    value: UUID