"""Agent domain models.

Immutable value objects representing agents, roles, and their configurations.
All fields are validated at construction time via Pydantic v2.
"""

from __future__ import annotations

from enum import StrEnum
from typing import Any

from pydantic import BaseModel
from pydantic import ConfigDict
from pydantic import Field


class AgentStatus(StrEnum):
    """Agent lifecycle states."""

    IDLE = "idle"
    RUNNING = "running"
    BLOCKED = "blocked"
    COMPLETED = "completed"
    FAILED = "failed"


class Role(BaseModel):
    """Role definition — what an agent can do.

    Attributes:
        name: Unique role identifier.
        description: Human-readable purpose.
        responsibilities: Ordered list of responsibilities.
        gates: Gate names this role participates in.
        rules: Rule file paths this role must follow.
    """

    model_config = ConfigDict(frozen=True)

    name: str
    description: str = ""
    responsibilities: list[str] = Field(default_factory=list)
    gates: list[str] = Field(default_factory=list)
    rules: list[str] = Field(default_factory=list)


class Agent(BaseModel):
    """Agent definition — a named entity assigned to roles.

    Attributes:
        name: Unique agent identifier.
        roles: Role names this agent can perform.
        description: Human-readable purpose.
        rules_path: Base path for rule resolution.
    """

    model_config = ConfigDict(frozen=True)

    name: str
    roles: list[str] = Field(default_factory=list)
    description: str = ""
    rules_path: str = ""


class GateChecklist(BaseModel):
    """Gate checklist — items that must pass before transition.

    Attributes:
        name: Unique gate identifier.
        from_role: Role initiating the gate.
        to_role: Role receiving the handoff.
        checklist: Ordered items to verify.
    """

    model_config = ConfigDict(frozen=True)

    name: str
    from_role: str
    to_role: str
    checklist: list[str] = Field(default_factory=list)


class TaskStatus(StrEnum):
    """Task lifecycle states."""

    OPEN = "open"
    IN_PROGRESS = "in_progress"
    BLOCKED = "blocked"
    COMPLETED = "completed"
    FAILED = "failed"


class Task(BaseModel):
    """Task — a unit of work flowing through the pipeline.

    Attributes:
        id: Unique task identifier.
        title: Short description.
        priority: Priority level.
        assigned: Agent name handling this task.
        status: Current lifecycle state.
        gate: Current gate name, if any.
        metadata: Arbitrary key-value pairs.
    """

    model_config = ConfigDict(frozen=True)

    id: str
    title: str
    priority: str = "MEDIUM"
    assigned: str = ""
    status: TaskStatus = TaskStatus.OPEN
    gate: str = ""
    metadata: dict[str, Any] = Field(default_factory=dict)
