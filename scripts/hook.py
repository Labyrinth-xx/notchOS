#!/usr/bin/env python3
"""Claude Code hook → fire-and-forget POST to notchOS backend.

Zero dependencies (stdlib only). Called by Claude Code for each hook event.
Usage: python3 hook.py <event_name>
Reads stdin JSON for session_id, tool_name, prompt text.
"""

import json
import socket
import sys

KNOWN_EVENTS = {
    "SessionStart", "SessionEnd", "UserPromptSubmit",
    "PreToolUse", "PostToolUse", "PostToolUseFailure",
    "Stop", "SubagentStart", "SubagentStop",
    "PreCompact", "PostCompact",
    "Notification", "PermissionRequest", "Elicitation",
    "WorktreeCreate",
}

event = sys.argv[1] if len(sys.argv) > 1 else ""
if event not in KNOWN_EVENTS:
    sys.exit(0)

session_id = "default"
tool_name = None
title = None
try:
    raw = sys.stdin.read()
    if raw:
        payload = json.loads(raw)
        session_id = payload.get("session_id", "default")
        tool_input = payload.get("tool_input", {})
        tool_name = payload.get("tool_name") or tool_input.get("tool_name")
        # Capture first user prompt as session title
        if event == "UserPromptSubmit":
            prompt = payload.get("prompt", "")
            if prompt:
                title = prompt[:60]
except json.JSONDecodeError as exc:
    print(f"notchOS hook: bad JSON from stdin: {exc}", file=sys.stderr)
except Exception:
    pass

body_bytes = json.dumps({
    "event": event,
    "session_id": session_id,
    "tool_name": tool_name,
    "title": title,
    "agent": "claude-code",
}).encode()

# Fire-and-forget: raw socket POST, don't wait for response
try:
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(0.3)
    sock.connect(("127.0.0.1", 23456))
    header = (
        f"POST /hook HTTP/1.0\r\n"
        f"Content-Type: application/json\r\n"
        f"Content-Length: {len(body_bytes)}\r\n"
        f"\r\n"
    ).encode()
    sock.sendall(header + body_bytes)
    sock.close()
except Exception:
    pass
