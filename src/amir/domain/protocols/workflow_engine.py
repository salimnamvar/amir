"""Workflow Engine Protocol - Interface for workflow orchestration."""

from abc import ABC, abstractmethod
from uuid import UUID
from typing import Optional


class WorkflowEngine(ABC):
    """
    Interface for workflow orchestration.
    Manages state transitions and task sequencing.
    """
    
    @abstractmethod
    async def create_workflow(
        self,
        template_id: UUID,
        team_id: UUID
    ) -> UUID:
        """
        Create workflow instance from template.
        Returns workflow_instance_id.
        """
        pass
    
    @abstractmethod
    async def next_state(
        self,
        workflow_id: UUID,
        completed_task_id: UUID,
        task_status: str
    ) -> Optional[str]:
        """
        Determine next workflow state.
        Returns next state name or None if complete.
        """
        pass
    
    @abstractmethod
    async def mark_state(
        self,
        workflow_id: UUID,
        state: str
    ) -> None:
        """
        Update workflow to specific state.
        """
        pass
    
    @abstractmethod
    async def get_state(
        self,
        workflow_id: UUID
    ) -> str:
        """
        Get current workflow state.
        """
        pass
    
    @abstractmethod
    async def complete(self, workflow_id: UUID) -> None:
        """
        Mark workflow as completed.
        """
        pass