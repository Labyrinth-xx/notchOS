"""Pydantic models for notchOS backend."""

from __future__ import annotations

from pydantic import BaseModel, Field

# Maps Claude Code hook events to display states
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
    """Incoming hook event from Claude Code."""

    event: str
    state: str
    session_id: str = "default"
    tool_name: str | None = None


class SessionState(BaseModel):
    """Tracked state of a single Claude Code session."""

    session_id: str
    state: str = "idle"
    project: str = "unknown"
    event: str = ""
    tool_name: str | None = None
    started_at: float = 0.0
    updated_at: float = 0.0


class NotchResponse(BaseModel):
    """Aggregated response for the notch UI."""

    sessions: list[SessionState] = Field(default_factory=list)
