"""FastAPI server for notchOS backend."""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager
from pathlib import Path
from typing import AsyncIterator

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

from backend.models import EVENT_TO_STATE, HookEvent, NotchResponse
from backend.state_manager import StateManager

logger = logging.getLogger(__name__)

UI_DIR = Path(__file__).resolve().parent.parent / "ui"

state_manager = StateManager()


@asynccontextmanager
async def lifespan(_app: FastAPI) -> AsyncIterator[None]:
    logger.info("notchOS backend starting on :23456")
    yield
    logger.info("notchOS backend shutting down")


app = FastAPI(title="notchOS", lifespan=lifespan)


@app.post("/hook")
async def receive_hook(event: HookEvent) -> JSONResponse:
    """Receive a hook event from Claude Code and derive state."""
    state = EVENT_TO_STATE.get(event.event)
    if state is None:
        return JSONResponse({"ok": False, "reason": "unknown event"})

    session = await state_manager.handle_hook(event, state)
    logger.info(
        "Hook: %s → %s [session=%s project=%s]",
        event.event,
        state,
        event.session_id[:8],
        session.project,
    )
    await state_manager.broadcast()
    return JSONResponse({"ok": True})


@app.websocket("/ws")
async def ws_endpoint(ws: WebSocket) -> None:
    """WebSocket: push state updates to connected UI clients."""
    await ws.accept()
    state_manager.add_ws(ws)
    try:
        # Send current state immediately on connect
        sessions = await state_manager.get_all()
        await ws.send_text(NotchResponse(sessions=sessions).model_dump_json())
        # Keep alive — wait for client disconnect
        while True:
            await ws.receive_text()
    except WebSocketDisconnect:
        pass
    finally:
        state_manager.remove_ws(ws)


@app.get("/api/state")
async def get_state() -> NotchResponse:
    """Return aggregated state for the notch UI."""
    sessions = await state_manager.get_all()
    return NotchResponse(sessions=sessions)


# Mount static UI files
if UI_DIR.is_dir():
    app.mount("/ui", StaticFiles(directory=str(UI_DIR), html=True), name="ui")
