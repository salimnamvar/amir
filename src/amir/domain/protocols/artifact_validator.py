"""Artifact Validator Protocol - Interface for artifact validation."""

from abc import ABC
from abc import abstractmethod
from uuid import UUID


class ArtifactValidator(ABC):
    """Interface for artifact validation.
    Validates structural, semantic, and security rules.
    """

    @abstractmethod
    async def validate(
        self, artifact_id: UUID, content: dict, contract_type: str, contract_version: str
    ) -> tuple[bool, list[str]]:
        """Validate artifact against contract.
        Returns (is_valid, list_of_errors).
        """

    @abstractmethod
    async def validate_schema(self, content: dict, contract_type: str, contract_version: str) -> tuple[bool, list[str]]:
        """Structural validation only (JSON Schema)."""

    @abstractmethod
    async def validate_semantic(self, content: dict, contract_type: str) -> tuple[bool, list[str]]:
        """Business rule validation."""

    @abstractmethod
    async def validate_security(self, content: dict) -> tuple[bool, list[str]]:
        """Security scan (no secrets, no malicious patterns)."""
