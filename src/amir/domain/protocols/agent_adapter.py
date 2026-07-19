"""Agent Adapter Protocol - Interface for agent execution."""

from abc import ABC, abstractmethod
from uuid import UUID
from typing import Optional, Any
from pydantic import BaseModel


class AgentInvocationContract(BaseModel):
    """Contract for agent invocation (runtime)."""
    invocation_id: UUID
    task_id: UUID
    contract_type: str
    contract_version: str
    input_payload: dict[str, Any]
    execution_parameters: dict[str, Any]  # timeout, max_tokens, streaming
    workspace: dict[str, Any]  # repo_url, branch, workdir


class AgentAdapter(ABC):
    """
    Abstract interface for agent adapters.
    Each adapter type (CLI, MCP, API) implements this.
    """
    
    @abstractmethod
    async def start_invocation(
        self,
        contract: AgentInvocationContract
    ) -> None:
        """
        Start agent execution.
        Should spawn process/container and return immediately.
        """
        pass
    
    @abstractmethod
    async def get_result(
        self,
        invocation_id: UUID,
        timeout: float = 30.0
    ) -> dict:
        """
        Get execution result.
        Returns artifact content or error.
        """
        pass
    
    @abstractmethod
    async def cancel(self, invocation_id: UUID) -> None:
        """
        Cancel running invocation.
        Best-effort cancellation.
        """
        pass
    
    @abstractmethod
    def supports_contract(self, contract_type: str, version: str) -> bool:
        """
        Check if adapter supports given contract.
        For capability matching.
        """
        pass