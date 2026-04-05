"""Canonical state and event definitions, loaded from shared/states.json."""

from __future__ import annotations

import enum
import json
from functools import lru_cache
from pathlib import Path

_STATES_FILE = Path(__file__).resolve().parent.parent / "shared" / "states.json"


class AgentState(str, enum.Enum):
    """All possible display states for an agent session."""

    IDLE = "idle"
    THINKING = "thinking"
    WORKING = "working"
    ERROR = "error"
    ATTENTION = "attention"
    NOTIFICATION = "notification"
    JUGGLING = "juggling"
    SWEEPING = "sweeping"
    CARRYING = "carrying"
    SLEEPING = "sleeping"


@lru_cache(maxsize=1)
def load_state_config() -> dict:
    """Load the shared state configuration (cached at first call)."""
    return json.loads(_STATES_FILE.read_text())


def default_state_for_event(event_name: str) -> AgentState | None:
    """Look up the default state for a hook event name. Returns None if unknown."""
    cfg = load_state_config()
    entry = cfg["events"].get(event_name)
    if entry is None:
        return None
    try:
        return AgentState(entry["default_state"])
    except ValueError:
        return None


def get_ttl(state_name: str) -> float | None:
    """Get the TTL (in seconds) for auto-downgrading a state. Returns None if no TTL."""
    cfg = load_state_config()
    return cfg["ttl"].get(state_name)
