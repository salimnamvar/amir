"""YAML-based repository implementations.

Reads agent/role/gate definitions from YAML config files.
Task state is stored in-memory for now (file-backed later).
"""

from __future__ import annotations

from typing import TYPE_CHECKING
from typing import Any

import yaml

from amir.contract.agent import Agent
from amir.contract.agent import GateChecklist
from amir.contract.agent import Role
from amir.contract.agent import Task

if TYPE_CHECKING:
    from pathlib import Path


def _load_yaml(path: Path) -> dict[str, Any]:
    """Load a YAML file and return parsed dict."""
    if not path.exists():
        return {}
    with path.open(encoding="utf-8") as f:
        loaded: Any = yaml.safe_load(f)
    if isinstance(loaded, dict):
        return dict(loaded)
    return {}


def _str(value: Any) -> str:
    return str(value) if value is not None else ""


def _str_list(value: Any) -> list[str]:
    if isinstance(value, list):
        return [str(item) for item in value]
    return []


class YamlAgentRepository:
    """Agent definitions loaded from team-config.yaml."""

    def __init__(self, config_path: Path) -> None:
        self._config = _load_yaml(config_path)
        self._agents = self._parse_agents()

    def _parse_agents(self) -> dict[str, Agent]:
        agents: dict[str, Agent] = {}
        raw = self._config.get("agents")
        if not isinstance(raw, dict):
            return agents
        for name, data in raw.items():
            if isinstance(data, dict):
                agents[_str(name)] = Agent(
                    name=_str(name),
                    roles=_str_list(data.get("roles")),
                    description=_str(data.get("description")),
                    rules_path=_str(data.get("rules_path")),
                )
        return agents

    def get_agent(self, name: str) -> Agent | None:
        return self._agents.get(name)

    def list_agents(self) -> list[Agent]:
        return list(self._agents.values())

    def save_agent(self, agent: Agent) -> None:
        self._agents[agent.name] = agent


class YamlRoleRepository:
    """Role definitions loaded from team-config.yaml."""

    def __init__(self, config_path: Path) -> None:
        self._config = _load_yaml(config_path)
        self._roles = self._parse_roles()

    def _parse_roles(self) -> dict[str, Role]:
        roles: dict[str, Role] = {}
        raw = self._config.get("roles")
        if not isinstance(raw, dict):
            return roles
        for name, data in raw.items():
            if isinstance(data, dict):
                roles[_str(name)] = Role(
                    name=_str(name),
                    description=_str(data.get("description")),
                    responsibilities=_str_list(data.get("responsibilities")),
                    gates=_str_list(data.get("gates")),
                    rules=_str_list(data.get("rules")),
                )
        return roles

    def get_role(self, name: str) -> Role | None:
        return self._roles.get(name)

    def list_roles(self) -> list[Role]:
        return list(self._roles.values())

    def save_role(self, role: Role) -> None:
        self._roles[role.name] = role


class YamlGateRepository:
    """Gate definitions loaded from team-config.yaml."""

    def __init__(self, config_path: Path) -> None:
        self._config = _load_yaml(config_path)
        self._gates = self._parse_gates()

    def _parse_gates(self) -> list[GateChecklist]:
        gates: list[GateChecklist] = []
        raw = self._config.get("gates")
        if not isinstance(raw, list):
            return gates
        for data in raw:
            if isinstance(data, dict):
                gates.append(
                    GateChecklist(
                        name=_str(data.get("name")),
                        from_role=_str(data.get("from")),
                        to_role=_str(data.get("to")),
                        checklist=_str_list(data.get("checklist")),
                    )
                )
        return gates

    def get_gate(self, name: str) -> GateChecklist | None:
        for gate in self._gates:
            if gate.name == name:
                return gate
        return None

    def list_gates(self) -> list[GateChecklist]:
        return list(self._gates)

    def save_gate(self, gate: GateChecklist) -> None:
        for i, existing in enumerate(self._gates):
            if existing.name == gate.name:
                self._gates[i] = gate
                return
        self._gates.append(gate)


class InMemoryTaskRepository:
    """In-memory task storage. Replace with file/DB backend later."""

    def __init__(self) -> None:
        self._tasks: dict[str, Task] = {}

    def get_task(self, task_id: str) -> Task | None:
        return self._tasks.get(task_id)

    def list_tasks(self, status: str | None = None) -> list[Task]:
        if status is None:
            return list(self._tasks.values())
        return [t for t in self._tasks.values() if t.status == status]

    def save_task(self, task: Task) -> None:
        self._tasks[task.id] = task

    def delete_task(self, task_id: str) -> None:
        self._tasks.pop(task_id, None)
