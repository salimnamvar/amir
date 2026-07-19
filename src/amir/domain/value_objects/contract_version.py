"""Contract Version value object."""

from pydantic import BaseModel, Field, field_validator
from typing import Optional


class ContractVersion(BaseModel):
    """
    Semantic version for contracts.
    Supports MAJOR.MINOR.PATCH format.
    """
    major: int = Field(ge=0)
    minor: int = Field(ge=0)
    patch: int = Field(ge=0)
    prerelease: Optional[str] = None
    
    @classmethod
    def parse(cls, version_str: str) -> "ContractVersion":
        """Parse version string into ContractVersion."""
        # Handle prerelease suffix (e.g., "1.0.0-beta")
        prerelease = None
        if "-" in version_str:
            version_str, prerelease = version_str.split("-", 1)
        
        parts = version_str.strip().split(".")
        if len(parts) < 3:
            raise ValueError(f"Invalid version format: {version_str}")
        
        major, minor, patch = int(parts[0]), int(parts[1]), int(parts[2])
        
        return cls(major=major, minor=minor, patch=patch, prerelease=prerelease)
    
    def __str__(self) -> str:
        base = f"{self.major}.{self.minor}.{self.patch}"
        if self.prerelease:
            return f"{base}-{self.prerelease}"
        return base
    
    def __lt__(self, other: "ContractVersion") -> bool:
        if self.major != other.major:
            return self.major < other.major
        if self.minor != other.minor:
            return self.minor < other.minor
        if self.patch != other.patch:
            return self.patch < other.patch
        return False
    
    def __le__(self, other: "ContractVersion") -> bool:
        return self == other or self < other
    
    def compatible_with(self, other: "ContractVersion") -> bool:
        """Check if version is compatible (same major)."""
        return self.major == other.major and self >= other