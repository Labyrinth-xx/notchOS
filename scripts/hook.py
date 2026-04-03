#!/usr/bin/env python3
"""Claude Code hook → POST to notchOS backend.

Zero dependencies (stdlib only). Called by Claude Code for each hook event.
Usage: python3 hook.py <event_name>
Reads stdin JSON from Claude Code for session_id.
"""

import json
import sys
import urllib.request

EVENT_TO_STATE = {
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

event = sys.argv[1] if len(sys.argv) > 1 else ""
state = EVENT_TO_STATE.get(event)
if not state:
    sys.exit(0)

session_id = "default"
tool_name = None
try:
    raw = sys.stdin.read()
    if raw:
        payload = json.loads(raw)
        session_id = payload.get("session_id", "default")
        tool_input = payload.get("tool_input", {})
        tool_name = payload.get("tool_name") or tool_input.get("tool_name")
except Exception:
    pass

data = json.dumps({
    "event": event,
    "state": state,
    "session_id": session_id,
    "tool_name": tool_name,
}).encode()

try:
    req = urllib.request.Request(
        "http://127.0.0.1:23456/hook",
        data=data,
        headers={"Content-Type": "application/json"},
    )
    urllib.request.urlopen(req, timeout=0.5)
except Exception:
    pass
