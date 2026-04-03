"""FastAPI server for notchOS backend."""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager
from pathlib import Path
from typing import AsyncIterator

from fastapi import FastAPI
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

from backend.models import HookEvent, NotchResponse
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
    """Receive a hook event from Claude Code."""
    session = await state_manager.handle_hook(event)
    logger.info(
        "Hook: %s → %s [session=%s project=%s]",
        event.event,
        event.state,
        event.session_id[:8],
        session.project,
    )
    return JSONResponse({"ok": True})


@app.get("/api/state")
async def get_state() -> NotchResponse:
    """Return aggregated state for the notch UI."""
    sessions = await state_manager.get_all()
    return NotchResponse(sessions=sessions)


# Mount static UI files
if UI_DIR.is_dir():
    app.mount("/ui", StaticFiles(directory=str(UI_DIR), html=True), name="ui")
