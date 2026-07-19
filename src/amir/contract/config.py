"""Configuration contract — validated settings models.

All configuration is loaded from YAML/env and validated at startup.
No implicit defaults, no silent failures.
"""

from __future__ import annotations

from pathlib import Path

from pydantic import BaseModel
from pydantic import ConfigDict
from pydantic import Field
from pydantic import field_validator


class LoggingConfig(BaseModel):
    """Logging configuration — level, transport, and file output.

    Attributes:
        level: Minimum log level (DEBUG, INFO, WARNING, ERROR, CRITICAL).
        async_logging: Enable async queue-based logging.
        log_dir: Directory for log files. None disables file logging.
        max_bytes: Maximum log file size before rotation.
        backup_count: Number of rotated log files to keep.
    """

    model_config = ConfigDict(frozen=True)

    level: str = Field(default="INFO", description="Minimum log level.")
    async_logging: bool = Field(default=True, description="Enable async queue logging.")
    log_dir: Path | None = Field(
        default=Path(".amir/log"),
        description="Directory for log files.",
    )
    max_bytes: int = Field(default=10 * 1024 * 1024, description="Max log file size (bytes).")
    backup_count: int = Field(default=5, description="Number of rotated backups.")

    @field_validator("level", mode="before")
    @classmethod
    def _validate_level(cls, a_value: object) -> str:
        if not isinstance(a_value, str):
            msg = "Logging level must be a string"
            raise TypeError(msg)
        normalized = a_value.upper()
        valid = {"DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"}
        if normalized not in valid:
            msg = f"Invalid logging level: {a_value}. Must be one of {valid}"
            raise ValueError(msg)
        return normalized


class TeamConfig(BaseModel):
    """Team configuration — agents, roles, and workflow gates.

    Attributes:
        name: Team identifier.
        agents: Agent definitions.
        roles: Role definitions.
        gates: Workflow gate definitions.
    """

    model_config = ConfigDict(frozen=True)

    name: str = ""
    agents: dict[str, dict[str, str]] = Field(default_factory=dict)
    roles: dict[str, dict[str, str]] = Field(default_factory=dict)
    gates: list[dict[str, str]] = []


class AmirConfig(BaseModel):
    """Root configuration — all settings in one validated model.

    Attributes:
        team: Team configuration.
        logging: Logging configuration.
    """

    model_config = ConfigDict(frozen=True)

    team: TeamConfig = Field(default_factory=TeamConfig)
    logging: LoggingConfig = Field(default_factory=LoggingConfig)
