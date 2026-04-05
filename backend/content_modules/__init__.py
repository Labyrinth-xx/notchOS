"""Content module registry for notchOS dynamic island features.

Each module defines how a specific content type renders in the UI.
Modules register themselves and are activated by the event router.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field


@dataclass(frozen=True)
class ContentPayload:
    """Data sent to the frontend for a content module to render."""

    module_id: str
    data: dict = field(default_factory=dict)
    priority: int = 0


class ContentModule(ABC):
    """Base class for content modules."""

    @property
    @abstractmethod
    def module_id(self) -> str:
        """Unique identifier matching the frontend JS module."""
        ...

    @abstractmethod
    def build_payload(self, event_data: dict) -> ContentPayload:
        """Build the payload to send to the frontend module."""
        ...


# Module registry
_registry: dict[str, ContentModule] = {}


def register_module(module: ContentModule) -> None:
    """Register a content module."""
    _registry[module.module_id] = module


def get_module(module_id: str) -> ContentModule | None:
    """Look up a registered module by ID."""
    return _registry.get(module_id)


def list_modules() -> list[str]:
    """Return all registered module IDs."""
    return list(_registry.keys())
