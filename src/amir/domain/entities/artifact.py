"""Artifact - Immutable output from agent execution."""

from datetime import datetime
from enum import Enum
import hashlib
import json
from typing import Any
from uuid import UUID
from uuid import uuid4

from pydantic import BaseModel
from pydantic import Field
from pydantic import field_validator


class ArtifactStatus(str, Enum):
    """Artifact lifecycle states."""

    PRODUCED = "produced"
    VALIDATING = "validating"
    ACCEPTED = "accepted"
    REJECTED = "rejected"


class Provenance(BaseModel):
    """Provenance metadata for artifact."""

    produced_by_agent_id: UUID
    session_id: UUID | None = None
    task_id: UUID
    workflow_instance_id: UUID | None = None
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    sandbox_id: UUID | None = None


class Artifact(BaseModel):
    """Immutable artifact produced by agent.
    Once validated and accepted, content never changes.

    Invariants:
    - Must reference valid contract type and version
    - Must include provenance metadata
    - Checksum must match content
    - Status transitions: produced → validating → accepted/rejected
    """

    id: UUID = Field(default_factory=uuid4)
    contract_type: str
    contract_version: str
    content: dict[str, Any]

    # Provenance (immutable)
    provenance: Provenance

    # Integrity
    checksum: str | None = None

    # Lifecycle
    status: ArtifactStatus = ArtifactStatus.PRODUCED

    # Validation results
    validation_errors: list[str] = Field(default_factory=list)

    @field_validator("checksum")
    @classmethod
    def compute_checksum(cls, v, info):
        """Auto-compute checksum if not provided."""
        if v is None and "content" in info.data:
            content_str = json.dumps(info.data["content"], sort_keys=True)
            return hashlib.sha256(content_str.encode()).hexdigest()
        return v

    def mark_validating(self) -> None:
        """Mark artifact as validating."""
        self.status = ArtifactStatus.VALIDATING

    def mark_accepted(self) -> None:
        """Mark artifact as accepted."""
        self.status = ArtifactStatus.ACCEPTED

    def mark_rejected(self, errors: list[str]) -> None:
        """Mark artifact as rejected with errors."""
        self.status = ArtifactStatus.REJECTED
        self.validation_errors = errors

    def to_json(self) -> str:
        """Export artifact as JSON."""
        return json.dumps(self.content, indent=2, default=str)
