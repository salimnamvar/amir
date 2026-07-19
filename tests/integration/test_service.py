"""Integration tests for agent service."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from amir.contract.agent import Agent, Task, TaskStatus
from amir.infrastructure.bootstrap import Amir
from amir.infrastructure.logging import StructuredLogSink
from amir.repository.yaml_repositories import InMemoryTaskRepository


class MockAgentRepo:
    """In-memory agent repository for testing."""

    def __init__(self) -> None:
        self._agents: dict[str, Agent] = {}

    def get_agent(self, name: str) -> Agent | None:
        return self._agents.get(name)

    def list_agents(self) -> list[Agent]:
        return list(self._agents.values())

    def save_agent(self, agent: Agent) -> None:
        self._agents[agent.name] = agent


class MockRoleRepo:
    """In-memory role repository for testing."""

    def __init__(self) -> None:
        self._roles: dict[str, Any] = {}

    def get_role(self, name: str) -> None:
        return None

    def list_roles(self) -> list[Any]:
        return []

    def save_role(self, role: Any) -> None:
        pass


class MockGateRepo:
    """In-memory gate repository for testing."""

    def __init__(self) -> None:
        self._gates: list[Any] = []

    def get_gate(self, name: str) -> None:
        return None

    def list_gates(self) -> list[Any]:
        return []

    def save_gate(self, gate: Any) -> None:
        pass


def test_bootstrap_from_config() -> None:
    config_path = Path(__file__).parent.parent.parent / "src" / "amir" / "agent" / "team-config.yaml"
    if not config_path.exists():
        return

    app = Amir.from_config_path(config_path)
    app.start()

    assert app.service is not None
    agents = app.service.list_agents()
    assert len(agents) > 0

    gates = app.service.list_gates_in_order()
    assert len(gates) > 0

    app.stop()


def test_agent_assignment() -> None:
    from amir.service.agent_service import AgentService

    agent_repo = MockAgentRepo()
    agent_repo.save_agent(Agent(name="mimo", roles=["tech-lead"]))

    role_repo = MockRoleRepo()
    gate_repo = MockGateRepo()

    task_repo = InMemoryTaskRepository()
    task_repo.save_task(Task(id="T1", title="Test task"))

    log_sink = StructuredLogSink()

    service = AgentService(
        agents=agent_repo,
        roles=role_repo,
        gates=gate_repo,
        tasks=task_repo,
        log=log_sink,
    )

    task = service.assign_agent_to_task("T1", "mimo")
    assert task.assigned == "mimo"
    assert task.status == TaskStatus.IN_PROGRESS
