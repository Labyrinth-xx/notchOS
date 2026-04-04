"""Pydantic models for notchOS backend."""

from __future__ import annotations

from pydantic import BaseModel, Field

# Agent identity: label, display name, brand color.
# Add new agents here — no other backend file needs to change.
AGENT_META: dict[str, dict[str, str]] = {
    "claude-code": {"label": "CC", "display": "Claude Code", "color": "#F59E0B"},
}

# Single source of truth: maps hook event names to display states.
# Reused across all agents (event names are agent-agnostic).
EVENT_TO_STATE: dict[str, str] = {
    "SessionStart": "idle",
    "SessionEnd": "sleeping",
    "UserPromptSubmit": "thinking",
    "PreToolUse": "working",
    "PostToolUse": "working",
    "PostToolUseFailure": "error",
    "Stop": "attention",
    "SubagentStart": "juggling",
    "SubagentStop": "working",
    "PreCompact": "sweeping",
    "PostCompact": "attention",
    "Notification": "notification",
    "PermissionRequest": "notification",
    "Elicitation": "notification",
    "WorktreeCreate": "carrying",
}


class HookEvent(BaseModel):
    """Incoming hook event from any AI coding agent."""

    event: str
    session_id: str = "default"
    tool_name: str | None = None
    title: str | None = None
    agent: str = "claude-code"
    cwd: str | None = None  # working directory, used for project name resolution


class SessionState(BaseModel):
    """Tracked state of a single AI agent session."""

    session_id: str
    state: str = "idle"
    project: str = "unknown"
    event: str = ""
    tool_name: str | None = None
    title: str | None = None
    agent: str = "claude-code"
    agent_label: str = "CC"
    agent_color: str = "#F59E0B"
    started_at: float = 0.0
    updated_at: float = 0.0


class NotchResponse(BaseModel):
    """Aggregated response for the notch UI."""

    sessions: list[SessionState] = Field(default_factory=list)
