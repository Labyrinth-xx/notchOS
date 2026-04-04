"""In-memory session state manager with TTL cleanup and WebSocket broadcast."""

from __future__ import annotations

import asyncio
import json
import logging
import time
from pathlib import Path

from fastapi import WebSocket

from backend.models import AGENT_META, HookEvent, NotchResponse, SessionState

logger = logging.getLogger(__name__)

SESSIONS_DIR = Path.home() / ".claude" / "sessions"
IDLE_TTL_SECONDS = 300       # 5 minutes
ATTENTION_TTL_SECONDS = 3.6  # matches CSS red-alert animation (3.5s) + 0.1s margin
NOTIFICATION_TTL_SECONDS = 5.6  # matches CSS notification-alert (5.5s) + 0.1s margin


class StateManager:
    """Tracks active Claude Code sessions in memory."""

    def __init__(self) -> None:
        self._sessions: dict[str, SessionState] = {}
        self._lock = asyncio.Lock()
        self._ws_clients: set[WebSocket] = set()
        self._attention_tasks: dict[str, asyncio.Task] = {}
        self._downgrade_epoch: dict[str, int] = {}  # epoch counter per session to prevent stale downgrades

    async def handle_hook(self, event: HookEvent, state: str) -> SessionState:
        """Update session state from a hook event. Returns updated state."""
        now = time.time()
        async with self._lock:
            existing = self._sessions.get(event.session_id)
            if existing is None:
                project = _resolve_project(event.session_id, cwd=event.cwd)
                meta = AGENT_META.get(event.agent, {})
                agent_label = meta.get("label", event.agent[:2].upper())
                agent_color = meta.get("color", "#888888")
                session = SessionState(
                    session_id=event.session_id,
                    state=state,
                    project=project,
                    event=event.event,
                    tool_name=event.tool_name,
                    title=event.title,
                    agent=event.agent,
                    agent_label=agent_label,
                    agent_color=agent_color,
                    started_at=now,
                    updated_at=now,
                )
            else:
                update: dict = {
                    "state": state,
                    "event": event.event,
                    "tool_name": event.tool_name,
                    "updated_at": now,
                }
                # Only set title on first UserPromptSubmit (don't overwrite)
                if event.title and not existing.title:
                    update["title"] = event.title
                session = existing.model_copy(update=update)

            if state == "sleeping":
                self._sessions.pop(event.session_id, None)
            else:
                self._sessions[event.session_id] = session

            # Cancel any pending downgrade for this session
            old_task = self._attention_tasks.pop(event.session_id, None)
            if old_task:
                old_task.cancel()

            # Bump epoch so stale tasks won't downgrade
            epoch = self._downgrade_epoch.get(event.session_id, 0) + 1
            self._downgrade_epoch[event.session_id] = epoch

            # Schedule auto-downgrade if entering attention or notification state
            if state == "attention":
                self._attention_tasks[event.session_id] = asyncio.create_task(
                    self._downgrade_state(event.session_id, "attention", ATTENTION_TTL_SECONDS, epoch)
                )
            elif state == "notification":
                self._attention_tasks[event.session_id] = asyncio.create_task(
                    self._downgrade_state(event.session_id, "notification", NOTIFICATION_TTL_SECONDS, epoch)
                )

            return session

    async def _downgrade_state(self, session_id: str, from_state: str, ttl: float, epoch: int) -> None:
        """After TTL, downgrade from_state → idle and broadcast. Skips if epoch is stale."""
        await asyncio.sleep(ttl)
        async with self._lock:
            # Only downgrade if this is still the latest epoch for this session
            if self._downgrade_epoch.get(session_id) != epoch:
                return
            s = self._sessions.get(session_id)
            if s and s.state == from_state:
                self._sessions[session_id] = s.model_copy(update={"state": "idle"})
        self._attention_tasks.pop(session_id, None)
        await self.broadcast()

    async def broadcast(self) -> None:
        """Push current state to all connected WebSocket clients."""
        if not self._ws_clients:
            return
        sessions = await self.get_all()
        payload = NotchResponse(sessions=sessions).model_dump_json()
        dead: list[WebSocket] = []
        for ws in list(self._ws_clients):  # snapshot to avoid RuntimeError on set mutation
            try:
                await ws.send_text(payload)
            except Exception:
                dead.append(ws)
        for ws in dead:
            self._ws_clients.discard(ws)

    def add_ws(self, ws: WebSocket) -> None:
        self._ws_clients.add(ws)

    def remove_ws(self, ws: WebSocket) -> None:
        self._ws_clients.discard(ws)

    async def get_all(self) -> list[SessionState]:
        """Return all active sessions, pruning stale ones and downgrading attention."""
        now = time.time()
        async with self._lock:
            stale_ids = [
                sid
                for sid, s in self._sessions.items()
                if s.state in ("idle", "sleeping")
                and (now - s.updated_at) > IDLE_TTL_SECONDS
            ]
            for sid in stale_ids:
                del self._sessions[sid]

            # Auto-downgrade attention/notification → idle after short timeout
            for sid, s in self._sessions.items():
                if s.state == "attention" and (now - s.updated_at) > ATTENTION_TTL_SECONDS:
                    self._sessions[sid] = s.model_copy(update={"state": "idle"})
                elif s.state == "notification" and (now - s.updated_at) > NOTIFICATION_TTL_SECONDS:
                    self._sessions[sid] = s.model_copy(update={"state": "idle"})

            return list(self._sessions.values())


def _resolve_project(session_id: str, cwd: str | None = None) -> str:
    """Resolve project name from cwd hint or Claude session metadata."""
    if cwd:
        return Path(cwd).name or "unknown"

    if not SESSIONS_DIR.is_dir():
        return "unknown"

    for path in SESSIONS_DIR.iterdir():
        if not path.suffix == ".json":
            continue
        try:
            data = json.loads(path.read_text())
            if data.get("sessionId") == session_id:
                session_cwd = data.get("cwd", "")
                return Path(session_cwd).name if session_cwd else "unknown"
        except (json.JSONDecodeError, OSError):
            continue

    return "unknown"
