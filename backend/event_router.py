"""Pluggable event routing with priority ordering and conditional dispatch."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Protocol

from backend.models import HookEvent, SessionState
from backend.states import AgentState, default_state_for_event


@dataclass(frozen=True)
class RouteResult:
    """Result of routing an event: state + optional content module activation."""

    state: str
    content_module: str | None = None
    payload: dict = field(default_factory=dict)


class EventHandler(Protocol):
    """Protocol for event handlers that can be registered with the router."""

    @property
    def priority(self) -> int:
        """Lower number = higher priority (checked first)."""
        ...

    def can_handle(self, event: HookEvent) -> bool:
        """Return True if this handler should process the event."""
        ...

    async def handle(self, event: HookEvent, current: SessionState | None) -> RouteResult:
        """Process the event and return a RouteResult."""
        ...


class DefaultStateHandler:
    """Fallback handler: maps events to states via shared/states.json."""

    @property
    def priority(self) -> int:
        return 100

    def can_handle(self, event: HookEvent) -> bool:
        return default_state_for_event(event.event) is not None

    async def handle(self, event: HookEvent, current: SessionState | None) -> RouteResult:
        agent_state = default_state_for_event(event.event)
        if agent_state is None:
            return RouteResult(state="idle")
        return RouteResult(state=agent_state.value)


class EventRouter:
    """Routes hook events through a priority-ordered handler chain."""

    def __init__(self) -> None:
        self._handlers: list[EventHandler] = []

    def register(self, handler: EventHandler) -> None:
        """Register a handler. Handlers are sorted by priority (lower = first)."""
        self._handlers.append(handler)
        self._handlers.sort(key=lambda h: h.priority)

    async def route(self, event: HookEvent, current: SessionState | None) -> RouteResult:
        """Route an event through handlers. First matching handler wins."""
        for handler in self._handlers:
            if handler.can_handle(event):
                return await handler.handle(event, current)
        # No handler matched — try default state mapping
        agent_state = default_state_for_event(event.event)
        if agent_state is not None:
            return RouteResult(state=agent_state.value)
        raise ValueError(f"No handler for event: {event.event}")
