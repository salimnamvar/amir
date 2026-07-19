"""Artifact Validator Protocol - Interface for artifact validation."""

from abc import ABC, abstractmethod
from uuid import UUID
from typing import Optional


class ArtifactValidator(ABC):
    """
    Interface for artifact validation.
    Validates structural, semantic, and security rules.
    """
    
    @abstractmethod
    async def validate(
        self,
        artifact_id: UUID,
        content: dict,
        contract_type: str,
        contract_version: str
    ) -> tuple[bool, list[str]]:
        """
        Validate artifact against contract.
        Returns (is_valid, list_of_errors).
        """
        pass
    
    @abstractmethod
    async def validate_schema(
        self,
        content: dict,
        contract_type: str,
        contract_version: str
    ) -> tuple[bool, list[str]]:
        """
        Structural validation only (JSON Schema).
        """
        pass
    
    @abstractmethod
    async def validate_semantic(
        self,
        content: dict,
        contract_type: str
    ) -> tuple[bool, list[str]]:
        """
        Business rule validation.
        """
        pass
    
    @abstractmethod
    async def validate_security(
        self,
        content: dict
    ) -> tuple[bool, list[str]]:
        """
        Security scan (no secrets, no malicious patterns).
        """
        pass