"""In-memory session state manager with TTL cleanup and WebSocket broadcast."""

from __future__ import annotations

import asyncio
import json
import logging
import time
from pathlib import Path

from fastapi import WebSocket

from backend.models import HookEvent, NotchResponse, SessionState

logger = logging.getLogger(__name__)

SESSIONS_DIR = Path.home() / ".claude" / "sessions"
IDLE_TTL_SECONDS = 300  # 5 minutes


class StateManager:
    """Tracks active Claude Code sessions in memory."""

    def __init__(self) -> None:
        self._sessions: dict[str, SessionState] = {}
        self._lock = asyncio.Lock()
        self._ws_clients: set[WebSocket] = set()

    async def handle_hook(self, event: HookEvent, state: str) -> SessionState:
        """Update session state from a hook event. Returns updated state."""
        now = time.time()
        async with self._lock:
            existing = self._sessions.get(event.session_id)
            if existing is None:
                project = _resolve_project(event.session_id)
                session = SessionState(
                    session_id=event.session_id,
                    state=state,
                    project=project,
                    event=event.event,
                    tool_name=event.tool_name,
                    title=event.title,
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

            return session

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
        """Return all active sessions, pruning stale ones."""
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

            return list(self._sessions.values())


def _resolve_project(session_id: str) -> str:
    """Try to resolve project name from Claude session metadata."""
    if not SESSIONS_DIR.is_dir():
        return "unknown"

    for path in SESSIONS_DIR.iterdir():
        if not path.suffix == ".json":
            continue
        try:
            data = json.loads(path.read_text())
            if data.get("sessionId") == session_id:
                cwd = data.get("cwd", "")
                return Path(cwd).name if cwd else "unknown"
        except (json.JSONDecodeError, OSError):
            continue

    return "unknown"
