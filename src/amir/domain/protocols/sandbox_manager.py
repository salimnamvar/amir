"""Sandbox Manager Protocol - Interface for isolated execution."""

from abc import ABC, abstractmethod
from uuid import UUID
from typing import Optional


class SandboxManager(ABC):
    """
    Interface for sandbox lifecycle management.
    MVP uses Docker containers.
    """
    
    @abstractmethod
    async def create_sandbox(
        self,
        task_id: UUID,
        agent_id: UUID,
        resource_limits: dict
    ) -> UUID:
        """
        Create isolated sandbox.
        Returns sandbox_id for tracking.
        """
        pass
    
    @abstractmethod
    async def destroy_sandbox(self, sandbox_id: UUID) -> None:
        """
        Destroy sandbox and cleanup resources.
        """
        pass
    
    @abstractmethod
    async def get_workspace_path(self, sandbox_id: UUID) -> str:
        """
        Get workspace path for sandbox.
        """
        pass
    
    @abstractmethod
    async def execute_in_sandbox(
        self,
        sandbox_id: UUID,
        command: list[str],
        timeout: int
    ) -> tuple[int, str, str]:
        """
        Execute command in sandbox.
        Returns (exit_code, stdout, stderr).
        """
        pass