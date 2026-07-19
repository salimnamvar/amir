"""Logging contract — structured log entry models.

Mirrors the formatting policy from the Python bootstrap:
  Diagnostic (< INFO):  LEVEL WHEN WHERE RESOURCE : MESSAGE
  Operational (>= INFO): LEVEL WHEN RESOURCE : MESSAGE
"""

from __future__ import annotations

from enum import StrEnum

from pydantic import BaseModel
from pydantic import ConfigDict
from pydantic import Field


class LogLevel(StrEnum):
    """Log severity levels."""

    DEBUG = "DEBUG"
    INFO = "INFO"
    WARNING = "WARNING"
    ERROR = "ERROR"
    CRITICAL = "CRITICAL"


class LogEntry(BaseModel):
    """Structured log entry — single observation record.

    Attributes:
        level: Severity level.
        timestamp: UTC ISO-8601 with microseconds.
        message: Human-readable observation.
        resource: Optional resource identifier (e.g., agent=mimo).
        source: File:line of the emitter (diagnostic only).
    """

    model_config = ConfigDict(frozen=True)

    level: LogLevel
    timestamp: str
    message: str
    resource: str = ""
    source: str = ""

    def format_operational(self) -> str:
        """Operational format: LEVEL WHEN RESOURCE : MESSAGE."""
        resource = f" {self.resource}" if self.resource else ""
        return f"{self.level.value} {self.timestamp}{resource} : {self.message}"

    def format_diagnostic(self) -> str:
        """Diagnostic format: LEVEL WHEN WHERE RESOURCE : MESSAGE."""
        resource = f" {self.resource}" if self.resource else ""
        source = f" {self.source}" if self.source else ""
        return f"{self.level.value} {self.timestamp}{source}{resource} : {self.message}"


class AgentEvent(BaseModel):
    """Agent lifecycle event — observation of agent activity.

    Attributes:
        kind: Event type (AGENT_START, AGENT_DONE, GATE_START, etc.).
        agent: Agent name.
        role: Role being performed.
        task: Task identifier.
        timestamp: UTC ISO-8601.
        details: Arbitrary event-specific data.
    """

    model_config = ConfigDict(frozen=True)

    kind: str
    agent: str = ""
    role: str = ""
    task: str = ""
    timestamp: str = ""
    details: dict[str, str] = Field(default_factory=dict)
