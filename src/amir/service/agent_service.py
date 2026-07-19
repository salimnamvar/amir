"""Agent service — orchestration logic for agent lifecycle.

Owns the business rules for assigning agents to roles,
resolving gate transitions, and managing task flow.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from amir.contract.agent import Agent
from amir.contract.agent import GateChecklist
from amir.contract.agent import Task
from amir.contract.agent import TaskStatus

if TYPE_CHECKING:
    from amir.contract.protocols import AgentRepository
    from amir.contract.protocols import GateRepository
    from amir.contract.protocols import LogSink
    from amir.contract.protocols import RoleRepository
    from amir.contract.protocols import TaskRepository


class AgentService:
    """Orchestrates agent assignment, gate transitions, and task flow.

    Dependencies are injected via protocols — no concrete imports.
    """

    def __init__(
        self,
        a_agents: AgentRepository,
        a_roles: RoleRepository,
        a_gates: GateRepository,
        a_tasks: TaskRepository,
        a_log: LogSink,
    ) -> None:
        self._agents = a_agents
        self._roles = a_roles
        self._gates = a_gates
        self._tasks = a_tasks
        self._log = a_log

    def assign_agent_to_task(self, a_task_id: str, a_agent_name: str) -> Task:
        """Assign an agent to a task. Validates agent exists and is idle.

        Args:
            a_task_id: Task identifier.
            a_agent_name: Agent to assign.

        Returns:
            Updated task.

        Raises:
            ValueError: If agent or task not found, or agent not idle.
        """
        agent = self._agents.get_agent(a_agent_name)
        if agent is None:
            msg = f"Agent not found: {a_agent_name}"
            raise ValueError(msg)

        task = self._tasks.get_task(a_task_id)
        if task is None:
            msg = f"Task not found: {a_task_id}"
            raise ValueError(msg)

        if task.status not in (TaskStatus.OPEN, TaskStatus.BLOCKED):
            msg = f"Task {a_task_id} is not assignable (status={task.status})"
            raise ValueError(msg)

        updated = task.model_copy(
            update={
                "assigned": a_agent_name,
                "status": TaskStatus.IN_PROGRESS,
            }
        )
        self._tasks.save_task(updated)
        self._log.write("INFO", f"AGENT_START agent={a_agent_name} task={a_task_id}", f"agent={a_agent_name}")
        return updated

    def resolve_agent_for_role(self, a_role_name: str) -> Agent | None:
        """Find the first agent assigned to a given role.

        Args:
            a_role_name: Role to search for.

        Returns:
            First matching agent, or None.
        """
        result: Agent | None = None
        for agent in self._agents.list_agents():
            if a_role_name in agent.roles:
                result = agent
                break
        return result

    def get_gate(self, a_gate_name: str) -> GateChecklist | None:
        """Retrieve a gate definition by name."""
        return self._gates.get_gate(a_gate_name)

    def list_gates_in_order(self) -> list[GateChecklist]:
        """Return all gates in definition order."""
        return self._gates.list_gates()

    def complete_gate(self, a_gate_name: str, a_task_id: str) -> Task:
        """Mark a gate as passed and transition task to next role.

        Args:
            a_gate_name: Gate that just passed.
            a_task_id: Task being transitioned.

        Returns:
            Updated task.

        Raises:
            ValueError: If gate or task not found.
        """
        gate = self._gates.get_gate(a_gate_name)
        if gate is None:
            msg = f"Gate not found: {a_gate_name}"
            raise ValueError(msg)

        task = self._tasks.get_task(a_task_id)
        if task is None:
            msg = f"Task not found: {a_task_id}"
            raise ValueError(msg)

        self._log.write("INFO", f"GATE_DONE gate={a_gate_name} status=success", f"gate={a_gate_name}")

        next_agent = self.resolve_agent_for_role(gate.to_role)
        updated = task.model_copy(
            update={
                "gate": "",
                "assigned": next_agent.name if next_agent else "",
            }
        )
        self._tasks.save_task(updated)

        if next_agent:
            self._log.write(
                "INFO",
                f"HANDOFF from={task.assigned} to={next_agent.name} task={a_task_id}",
                "resource=collaboration",
            )

        return updated

    def get_task(self, a_task_id: str) -> Task | None:
        """Retrieve a task by ID."""
        return self._tasks.get_task(a_task_id)

    def list_tasks(self, a_status: str | None = None) -> list[Task]:
        """List tasks, optionally filtered by status."""
        return self._tasks.list_tasks(a_status)

    def list_agents(self) -> list[Agent]:
        """List all registered agents."""
        return self._agents.list_agents()
