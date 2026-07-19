"""Unit tests for contract models."""

import contextlib

from amir.contract.agent import Agent, GateChecklist, Role, Task, TaskStatus


def test_agent_creation():
    agent = Agent(name="mimo", roles=["tech-lead", "qa-engineer"])
    assert agent.name == "mimo"
    assert agent.roles == ["tech-lead", "qa-engineer"]


def test_role_creation():
    role = Role(name="tech-lead", description="Architecture decisions")
    assert role.name == "tech-lead"
    assert role.responsibilities == []


def test_gate_creation():
    gate = GateChecklist(
        name="design_approval",
        from_role="tech-lead",
        to_role="coder",
        checklist=["Architecture documented", "Criteria defined"],
    )
    assert gate.name == "design_approval"
    assert len(gate.checklist) == 2


def test_task_creation():
    task = Task(id="T1", title="Fix token budget")
    assert task.id == "T1"
    assert task.status == TaskStatus.OPEN
    assert task.priority == "MEDIUM"


def test_task_status_transitions():
    task = Task(id="T1", title="Test")
    assert task.status == TaskStatus.OPEN

    updated = task.model_copy(update={"status": TaskStatus.IN_PROGRESS})
    assert updated.status == TaskStatus.IN_PROGRESS


def test_models_are_frozen():
    agent = Agent(name="test")
    with contextlib.suppress(Exception):
        agent.name = "other"  # type: ignore[misc]
    assert agent.name == "test"
