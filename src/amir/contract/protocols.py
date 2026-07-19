"""Protocol definitions — interface contracts for dependency inversion.

Services depend on protocols, not implementations.
Repositories implement protocols. Infrastructure wires them together.
"""

from __future__ import annotations

from typing import TYPE_CHECKING
from typing import Protocol
from typing import runtime_checkable

if TYPE_CHECKING:
    from amir.contract.agent import Agent
    from amir.contract.agent import GateChecklist
    from amir.contract.agent import Role
    from amir.contract.agent import Task


@runtime_checkable
class AgentRepository(Protocol):
    """Storage interface for agent definitions."""

    def get_agent(self, name: str) -> Agent | None: ...

    def list_agents(self) -> list[Agent]: ...

    def save_agent(self, agent: Agent) -> None: ...


@runtime_checkable
class RoleRepository(Protocol):
    """Storage interface for role definitions."""

    def get_role(self, name: str) -> Role | None: ...

    def list_roles(self) -> list[Role]: ...

    def save_role(self, role: Role) -> None: ...


@runtime_checkable
class GateRepository(Protocol):
    """Storage interface for gate definitions."""

    def get_gate(self, name: str) -> GateChecklist | None: ...

    def list_gates(self) -> list[GateChecklist]: ...

    def save_gate(self, gate: GateChecklist) -> None: ...


@runtime_checkable
class TaskRepository(Protocol):
    """Storage interface for task state."""

    def get_task(self, task_id: str) -> Task | None: ...

    def list_tasks(self, status: str | None = None) -> list[Task]: ...

    def save_task(self, task: Task) -> None: ...

    def delete_task(self, task_id: str) -> None: ...


@runtime_checkable
class LogSink(Protocol):
    """Output interface for structured log entries."""

    def write(self, level: str, message: str, resource: str = "") -> None: ...

    def flush(self) -> None: ...
