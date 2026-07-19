"""Agent Definition Aggregate - Immutable agent configuration."""

from pydantic import BaseModel, Field, field_validator
from uuid import UUID, uuid4
from datetime import datetime
from typing import Optional, Any
from enum import Enum


class AdapterType(str, Enum):
    """Supported adapter types."""
    CLI = "cli"
    MCP = "mcp"
    API = "api"


class AgentDefinitionStatus(str, Enum):
    """Agent definition lifecycle."""
    DRAFT = "draft"
    PUBLISHED = "published"
    DEPRECATED = "deprecated"


class Proficiency(str, Enum):
    """Skill proficiency levels."""
    NOVICE = "novice"
    INTERMEDIATE = "intermediate"
    EXPERT = "expert"


class ToolConstraint(BaseModel):
    """Constraints for tool usage."""
    max_calls: Optional[int] = None
    rate_limit_per_minute: Optional[int] = None


class ToolAvailability(BaseModel):
    """Tool availability with constraints."""
    name: str
    available: bool = True
    constraints: Optional[ToolConstraint] = None


class Capability(BaseModel):
    """
    Agent capability declaration.
    Skills and tools the agent can perform.
    """
    skill: str
    proficiency: Proficiency = Proficiency.INTERMEDIATE
    languages: list[str] = Field(default_factory=list)
    tools: list[ToolAvailability] = Field(default_factory=list)
    
    # Minimum required for MVP
    @field_validator('proficiency')
    @classmethod
    def validate_proficiency(cls, v):
        return v


class SecurityProfile(BaseModel):
    """Security requirements for agent execution."""
    sandbox_required: bool = True
    network_access: str = "limited"  # none, limited, full
    allowed_endpoints: list[str] = Field(default_factory=list)
    privileged_actions: list[str] = Field(default_factory=list)


class ResourceLimits(BaseModel):
    """Resource limits for agent execution."""
    max_context_tokens: int = Field(default=100000, gt=0)
    max_output_tokens: int = Field(default=4000, gt=0)
    timeout_seconds: int = Field(default=3600, gt=0)
    memory_limit_mb: Optional[int] = None
    cpu_limit_cores: Optional[float] = None


class AdapterConfig(BaseModel):
    """Adapter-specific configuration."""
    binary_path: Optional[str] = None
    working_directory: Optional[str] = None
    endpoint: Optional[str] = None
    protocol: Optional[str] = None
    auth_method: str = "none"


class NetworkLimit(str, Enum):
    """Network access constraints."""
    NONE = "none"
    LIMITED = "limited"
    FULL = "full"


class AgentDefinition(BaseModel):
    """
    Agent definition aggregate root.
    Immutable configuration for an agent type.
    
    Invariants:
    - Adapter config must match adapter_type
    - If sandbox_required=True, network must be limited or none
    - All capabilities must be valid skill names
    """
    id: UUID = Field(default_factory=uuid4)
    name: str = Field(..., min_length=1, max_length=100)
    description: Optional[str] = None
    
    adapter_type: AdapterType
    adapter_config: AdapterConfig
    
    # Capabilities are immutable after publish
    capabilities: list[Capability] = Field(default_factory=list)
    
    # Resource constraints
    resource_limits: ResourceLimits = Field(default_factory=ResourceLimits)
    
    # Security profile
    security_profile: SecurityProfile = Field(default_factory=SecurityProfile)
    
    # Metadata
    version: str = "1.0.0"
    status: AgentDefinitionStatus = AgentDefinitionStatus.DRAFT
    vendor: Optional[str] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)
    
    @field_validator('name')
    @classmethod
    def name_must_be_lowercase(cls, v):
        if v != v.lower():
            raise ValueError('Agent name must be lowercase')
        return v
    
    def supports_skill(self, skill: str, minimum_proficiency: Proficiency = None) -> bool:
        """Check if agent has required skill at required level."""
        proficiency_order = {
            Proficiency.NOVICE: 1,
            Proficiency.INTERMEDIATE: 2,
            Proficiency.EXPERT: 3
        }
        
        for cap in self.capabilities:
            if cap.skill == skill:
                if minimum_proficiency is None:
                    return True
                if proficiency_order.get(cap.proficiency, 0) >= proficiency_order.get(minimum_proficiency, 0):
                    return True
        return False
    
    def has_tool(self, tool_name: str) -> bool:
        """Check if agent has required tool available."""
        for cap in self.capabilities:
            for tool in cap.tools:
                if tool.name == tool_name and tool.available:
                    return True
        return False
    
    def can_execute(self) -> bool:
        """Check if agent is available for execution."""
        return self.status == AgentDefinitionStatus.PUBLISHED and self.security_profile.sandbox_required