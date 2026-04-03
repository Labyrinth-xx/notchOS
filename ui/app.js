/**
 * notchOS — Notch UI
 * Polls backend for session state and renders pill / dashboard.
 */

const API_URL = "http://127.0.0.1:23456/api/state";
const POLL_COLLAPSED = 2000;
const POLL_EXPANDED = 1000;

let isExpanded = false;
let pollTimer = null;

// Elements
const pill = document.getElementById("pill");
const pillDot = document.getElementById("pillDot");
const pillText = document.getElementById("pillText");
const pillCount = document.getElementById("pillCount");
const dashboard = document.getElementById("dashboard");
const sessionCount = document.getElementById("sessionCount");
const sessionsList = document.getElementById("sessionsList");

// Called by Swift via evaluateJavaScript
window.notchSetExpanded = function (expanded) {
  isExpanded = expanded;
  pill.classList.toggle("hidden", expanded);
  dashboard.classList.toggle("visible", expanded);
  restartPolling();
};

// Elapsed time helper
function formatElapsed(startedAt) {
  const seconds = Math.floor(Date.now() / 1000 - startedAt);
  if (seconds < 60) return `${seconds}s`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.floor(minutes / 60);
  return `${hours}h ${minutes % 60}m`;
}

// Pick the "most active" state from sessions for the pill dot
function dominantState(sessions) {
  const priority = [
    "error", "attention", "notification",
    "thinking", "working", "juggling",
    "sweeping", "carrying", "idle", "sleeping"
  ];
  for (const state of priority) {
    if (sessions.some((s) => s.state === state)) return state;
  }
  return "empty";
}

// Render pill (collapsed state)
function renderPill(sessions) {
  if (sessions.length === 0) {
    pillDot.className = "status-dot empty";
    pillText.textContent = "No sessions";
    pillCount.textContent = "";
    return;
  }

  const dominant = dominantState(sessions);
  pillDot.className = `status-dot ${dominant}`;

  if (sessions.length === 1) {
    const s = sessions[0];
    pillText.textContent = `${s.project} · ${s.state}`;
    pillCount.textContent = s.tool_name ? s.tool_name : "";
  } else {
    pillText.textContent = `${sessions.length} sessions`;
    pillCount.textContent = dominant;
  }
}

// Render dashboard (expanded state)
function renderDashboard(sessions) {
  sessionCount.textContent = `${sessions.length} active`;

  if (sessions.length === 0) {
    sessionsList.innerHTML = '<div class="empty-state">No active sessions</div>';
    return;
  }

  sessionsList.innerHTML = sessions
    .map((s) => {
      const elapsed = formatElapsed(s.started_at);
      const toolInfo = s.tool_name ? `<span class="session-tool">${escapeHtml(s.tool_name)}</span>` : "";
      return `
        <div class="session-card">
          <div class="status-dot ${s.state}"></div>
          <div class="session-info">
            <div class="session-project">${escapeHtml(s.project)}</div>
            <div class="session-detail">
              <span class="session-state ${s.state}">${s.state}</span>
              ${toolInfo}
            </div>
          </div>
          <span class="session-time">${elapsed}</span>
        </div>
      `;
    })
    .join("");
}

function escapeHtml(str) {
  const el = document.createElement("span");
  el.textContent = str;
  return el.innerHTML;
}

// Poll backend
async function fetchState() {
  try {
    const res = await fetch(API_URL);
    const data = await res.json();
    const sessions = data.sessions || [];

    renderPill(sessions);
    if (isExpanded) {
      renderDashboard(sessions);
    }
  } catch {
    // Backend not running — show offline
    pillDot.className = "status-dot empty";
    pillText.textContent = "Backend offline";
    pillCount.textContent = "";
    if (isExpanded) {
      sessionsList.innerHTML = '<div class="empty-state">Backend offline</div>';
    }
  }
}

function restartPolling() {
  if (pollTimer) clearInterval(pollTimer);
  const interval = isExpanded ? POLL_EXPANDED : POLL_COLLAPSED;
  pollTimer = setInterval(fetchState, interval);
  fetchState(); // immediate
}

// Start
restartPolling();
