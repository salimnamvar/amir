"""Bootstrap — application wiring and startup.

Instantiates repositories, services, and infrastructure.
Called once at process entry point.
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from amir.contract.config import LoggingConfig
from amir.infrastructure.logging import StructuredLogSink
from amir.infrastructure.logging import configure_logging
from amir.repository.yaml_repositories import InMemoryTaskRepository
from amir.repository.yaml_repositories import YamlAgentRepository
from amir.repository.yaml_repositories import YamlGateRepository
from amir.repository.yaml_repositories import YamlRoleRepository
from amir.service.agent_service import AgentService

if TYPE_CHECKING:
    from pathlib import Path

    from amir.contract.protocols import AgentRepository
    from amir.contract.protocols import GateRepository
    from amir.contract.protocols import LogSink
    from amir.contract.protocols import RoleRepository
    from amir.contract.protocols import TaskRepository


class Amir:
    """Application root — holds wired dependencies.

    Usage:
        app = Amir.from_config_path(Path("team-config.yaml"))
        app.start()
        # ... use app.service ...
        app.stop()
    """

    def __init__(
        self,
        agent_repo: AgentRepository,
        role_repo: RoleRepository,
        gate_repo: GateRepository,
        task_repo: TaskRepository,
        log_sink: LogSink,
        logging_config: LoggingConfig,
    ) -> None:
        self._agent_repo = agent_repo
        self._role_repo = role_repo
        self._gate_repo = gate_repo
        self._task_repo = task_repo
        self._log_sink = log_sink
        self._logging_config = logging_config
        self._listener = None
        self.service: AgentService | None = None

    @classmethod
    def from_config_path(cls, config_path: Path) -> Amir:
        """Create Amir from a team-config.yaml path."""
        agent_repo = YamlAgentRepository(config_path)
        role_repo = YamlRoleRepository(config_path)
        gate_repo = YamlGateRepository(config_path)
        task_repo = InMemoryTaskRepository()
        log_sink = StructuredLogSink()

        logging_config = LoggingConfig()

        return cls(
            agent_repo=agent_repo,
            role_repo=role_repo,
            gate_repo=gate_repo,
            task_repo=task_repo,
            log_sink=log_sink,
            logging_config=logging_config,
        )

    def start(self) -> None:
        """Initialize logging and create the service."""
        self._listener = configure_logging(self._logging_config)
        self.service = AgentService(
            agents=self._agent_repo,
            roles=self._role_repo,
            gates=self._gate_repo,
            tasks=self._task_repo,
            log=self._log_sink,
        )

    def stop(self) -> None:
        """Shut down logging listener."""
        if self._listener is not None:
            self._listener.stop()
            self._listener = None
