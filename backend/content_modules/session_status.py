"""Session status module — the default content module.

Displays session cards in the dashboard and status in the pill.
This wraps the existing rendering behavior as a module.
"""

from __future__ import annotations

from backend.content_modules import ContentModule, ContentPayload, register_module


class SessionStatusModule(ContentModule):
    """Default module: shows session status cards."""

    @property
    def module_id(self) -> str:
        return "session_status"

    def build_payload(self, event_data: dict) -> ContentPayload:
        return ContentPayload(
            module_id=self.module_id,
            data=event_data,
        )


# Auto-register on import
register_module(SessionStatusModule())
