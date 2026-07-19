"""YAML-based repository implementations.

Reads agent/role/gate definitions from YAML config files.
Task state is stored in-memory for now (file-backed later).
"""

from __future__ import annotations

from typing import TYPE_CHECKING
from typing import Any
from typing import cast

import yaml

from amir.contract.agent import Agent
from amir.contract.agent import GateChecklist
from amir.contract.agent import Role
from amir.contract.agent import Task

if TYPE_CHECKING:
    from pathlib import Path

YamlDict = dict[str, Any]


def _load_yaml(a_path: Path) -> YamlDict:
    """Load a YAML file and return parsed dict."""
    result: YamlDict = {}
    if a_path.exists():
        with a_path.open(encoding="utf-8") as f:
            loaded = yaml.safe_load(f)
        if isinstance(loaded, dict):
            result = cast("YamlDict", loaded)
    return result


def _str(a_value: Any) -> str:
    return str(a_value) if a_value is not None else ""


def _str_list(a_value: Any) -> list[str]:
    result: list[str] = []
    if isinstance(a_value, list):
        for item in cast("list[object]", a_value):
            result.append(str(item))
    return result


class YamlAgentRepository:
    """Agent definitions loaded from team-config.yaml."""

    def __init__(self, a_config_path: Path) -> None:
        self._config = _load_yaml(a_config_path)
        self._agents = self._parse_agents()

    def _parse_agents(self) -> dict[str, Agent]:
        agents: dict[str, Agent] = {}
        raw = self._config.get("agents")
        if isinstance(raw, dict):
            raw_dict = cast("YamlDict", raw)
            for name, data in raw_dict.items():
                if isinstance(data, dict):
                    data_dict = cast("YamlDict", data)
                    agents[_str(name)] = Agent(
                        name=_str(name),
                        roles=_str_list(data_dict.get("roles")),
                        description=_str(data_dict.get("description")),
                        rules_path=_str(data_dict.get("rules_path")),
                    )
        return agents

    def get_agent(self, a_name: str) -> Agent | None:
        return self._agents.get(a_name)

    def list_agents(self) -> list[Agent]:
        return list(self._agents.values())

    def save_agent(self, a_agent: Agent) -> None:
        self._agents[a_agent.name] = a_agent


class YamlRoleRepository:
    """Role definitions loaded from team-config.yaml."""

    def __init__(self, a_config_path: Path) -> None:
        self._config = _load_yaml(a_config_path)
        self._roles = self._parse_roles()

    def _parse_roles(self) -> dict[str, Role]:
        roles: dict[str, Role] = {}
        raw = self._config.get("roles")
        if isinstance(raw, dict):
            raw_dict = cast("YamlDict", raw)
            for name, data in raw_dict.items():
                if isinstance(data, dict):
                    data_dict = cast("YamlDict", data)
                    roles[_str(name)] = Role(
                        name=_str(name),
                        description=_str(data_dict.get("description")),
                        responsibilities=_str_list(data_dict.get("responsibilities")),
                        gates=_str_list(data_dict.get("gates")),
                        rules=_str_list(data_dict.get("rules")),
                    )
        return roles

    def get_role(self, a_name: str) -> Role | None:
        return self._roles.get(a_name)

    def list_roles(self) -> list[Role]:
        return list(self._roles.values())

    def save_role(self, a_role: Role) -> None:
        self._roles[a_role.name] = a_role


class YamlGateRepository:
    """Gate definitions loaded from team-config.yaml."""

    def __init__(self, a_config_path: Path) -> None:
        self._config = _load_yaml(a_config_path)
        self._gates = self._parse_gates()

    def _parse_gates(self) -> list[GateChecklist]:
        gates: list[GateChecklist] = []
        raw = self._config.get("gates")
        if isinstance(raw, list):
            for data in cast("list[object]", raw):
                if isinstance(data, dict):
                    data_dict = cast("YamlDict", data)
                    gates.append(
                        GateChecklist(
                            name=_str(data_dict.get("name")),
                            from_role=_str(data_dict.get("from")),
                            to_role=_str(data_dict.get("to")),
                            checklist=_str_list(data_dict.get("checklist")),
                        )
                    )
        return gates

    def get_gate(self, a_name: str) -> GateChecklist | None:
        result: GateChecklist | None = None
        for gate in self._gates:
            if gate.name == a_name:
                result = gate
        return result

    def list_gates(self) -> list[GateChecklist]:
        return list(self._gates)

    def save_gate(self, a_gate: GateChecklist) -> None:
        for i, existing in enumerate(self._gates):
            if existing.name == a_gate.name:
                self._gates[i] = a_gate
                break
        else:
            self._gates.append(a_gate)


class InMemoryTaskRepository:
    """In-memory task storage. Replace with file/DB backend later."""

    def __init__(self) -> None:
        self._tasks: dict[str, Task] = {}

    def get_task(self, a_task_id: str) -> Task | None:
        return self._tasks.get(a_task_id)

    def list_tasks(self, a_status: str | None = None) -> list[Task]:
        result = list(self._tasks.values())
        if a_status is not None:
            result = [t for t in result if t.status == a_status]
        return result

    def save_task(self, a_task: Task) -> None:
        self._tasks[a_task.id] = a_task

    def delete_task(self, a_task_id: str) -> None:
        self._tasks.pop(a_task_id, None)
