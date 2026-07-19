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

    def get_agent(self, a_name: str) -> Agent | None: ...

    def list_agents(self) -> list[Agent]: ...

    def save_agent(self, a_agent: Agent) -> None: ...


@runtime_checkable
class RoleRepository(Protocol):
    """Storage interface for role definitions."""

    def get_role(self, a_name: str) -> Role | None: ...

    def list_roles(self) -> list[Role]: ...

    def save_role(self, a_role: Role) -> None: ...


@runtime_checkable
class GateRepository(Protocol):
    """Storage interface for gate definitions."""

    def get_gate(self, a_name: str) -> GateChecklist | None: ...

    def list_gates(self) -> list[GateChecklist]: ...

    def save_gate(self, a_gate: GateChecklist) -> None: ...


@runtime_checkable
class TaskRepository(Protocol):
    """Storage interface for task state."""

    def get_task(self, a_task_id: str) -> Task | None: ...

    def list_tasks(self, a_status: str | None = None) -> list[Task]: ...

    def save_task(self, a_task: Task) -> None: ...

    def delete_task(self, a_task_id: str) -> None: ...


@runtime_checkable
class LogSink(Protocol):
    """Output interface for structured log entries."""

    def write(self, a_level: str, a_message: str, a_resource: str = "") -> None: ...

    def flush(self) -> None: ...
