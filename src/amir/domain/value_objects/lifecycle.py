"""Entity lifecycle value object."""

from enum import Enum


class EntityLifecycle(str, Enum):
    """Lifecycle states for different entity types."""

    # Configuration entities
    DRAFT = "draft"
    PUBLISHED = "published"
    DEPRECATED = "deprecated"

    # Runtime entities
    PENDING = "pending"
    ACTIVE = "active"
    COMPLETED = "completed"
    FAILED = "failed"
