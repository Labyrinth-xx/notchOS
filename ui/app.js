/**
 * notchOS — Notch UI
 * WebSocket-first with polling fallback for session state.
 */

const WS_URL = "ws://127.0.0.1:23456/ws";
const API_URL = "http://127.0.0.1:23456/api/state";

// Agent identity map — mirrors backend AGENT_META.
// Add new agents here when they're added to backend/models.py.
const AGENT_META = {
  "claude-code": { label: "CC", color: "#F59E0B" },
};
const POLL_FALLBACK = 5000;
const RECONNECT_DELAY = 3000;

let isExpanded = false;
let pollTimer = null;
let ws = null;
let wsConnected = false;

// Track previous states per session for transition detection
const previousStates = new Map();

// Elements
const pill = document.getElementById("pill");
const pillDot = document.getElementById("pillDot");
const pillText = document.getElementById("pillText");
const pillCount = document.getElementById("pillCount");
const dashboard = document.getElementById("dashboard");
const sessionCount = document.getElementById("sessionCount");
const sessionsList = document.getElementById("sessionsList");
const wingLeft = document.getElementById("wingLeft");
const wingRight = document.getElementById("wingRight");
const pillGlow = document.getElementById("pillGlow");

// ===== Swift Bridge =====

// Called by Swift via evaluateJavaScript
window.notchSetExpanded = function (expanded) {
  isExpanded = expanded;
  pill.classList.toggle("hidden", expanded);
  pillGlow.classList.toggle("hidden", expanded);
  dashboard.classList.toggle("visible", expanded);
  if (!wsConnected) restartPolling();
};

// ===== WebSocket =====

function connectWebSocket() {
  if (ws && ws.readyState <= WebSocket.OPEN) return;

  ws = new WebSocket(WS_URL);

  ws.onopen = function () {
    wsConnected = true;
    stopPolling();
  };

  ws.onmessage = function (evt) {
    try {
      const data = JSON.parse(evt.data);
      handleStateUpdate(data.sessions || []);
    } catch { /* ignore malformed messages */ }
  };

  ws.onclose = function () {
    wsConnected = false;
    ws = null;
    restartPolling();
    setTimeout(connectWebSocket, RECONNECT_DELAY);
  };

  ws.onerror = function () {
    ws.close();
  };
}

// ===== State Update =====

function handleStateUpdate(sessions) {
  // Detect state transitions for sound effects
  for (const s of sessions) {
    const prev = previousStates.get(s.session_id);
    if (prev && prev !== s.state) {
      onStateTransition(s.session_id, prev, s.state);
    }
    previousStates.set(s.session_id, s.state);
  }

  // Clean up sessions that disappeared
  const activeIds = new Set(sessions.map((s) => s.session_id));
  for (const id of previousStates.keys()) {
    if (!activeIds.has(id)) previousStates.delete(id);
  }

  renderPill(sessions);
  if (isExpanded) renderDashboard(sessions);
}

// Sound + confetti trigger on state transition
function onStateTransition(sessionId, fromState, toState) {
  const workingStates = new Set(["working", "thinking", "juggling"]);
  const doneStates = new Set(["idle", "sleeping", "attention"]);

  if (workingStates.has(fromState) && doneStates.has(toState)) {
    notifySwift("playSound", "complete");
    if (isExpanded) triggerConfetti();
  } else if (toState === "error") {
    notifySwift("playSound", "error");
  } else if (toState === "notification") {
    notifySwift("playSound", "attention");
  }
}

function notifySwift(type, value) {
  try {
    window.webkit.messageHandlers.notch.postMessage({ type, value });
  } catch { /* Swift bridge not available */ }
}

// ===== Rendering =====

function formatElapsed(startedAt) {
  const seconds = Math.floor(Date.now() / 1000 - startedAt);
  if (seconds < 60) return `${seconds}s`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.floor(minutes / 60);
  return `${hours}h ${minutes % 60}m`;
}

function dominantState(sessions) {
  const priority = [
    "error", "attention", "notification",
    "thinking", "working", "juggling",
    "sweeping", "carrying", "idle", "sleeping",
  ];
  for (const state of priority) {
    if (sessions.some((s) => s.state === state)) return state;
  }
  return "empty";
}

function injectFreezeKeyframe(capturedShadow) {
  // Extract RGB values from the current computed box-shadow
  const colorPattern = /rgba?\((\d+),\s*(\d+),\s*(\d+)/g;
  const matches = [...capturedShadow.matchAll(colorPattern)];
  const inner = matches.length >= 1 ? `${matches[0][1]},${matches[0][2]},${matches[0][3]}` : "168,85,247";
  const outer = matches.length >= 2 ? `${matches[1][1]},${matches[1][2]},${matches[1][3]}` : "90,108,240";

  const lo = `0 0 14px 5px rgba(${inner},0.5), 0 0 32px 12px rgba(${outer},0.25)`;
  const hi = `0 0 22px 10px rgba(${inner},0.8), 0 0 48px 18px rgba(${outer},0.4)`;
  const dim = `0 0 6px 2px rgba(${inner},0.1), 0 0 12px 4px rgba(${outer},0.05)`;

  let el = document.getElementById("freeze-style");
  if (!el) {
    el = document.createElement("style");
    el.id = "freeze-style";
    document.head.appendChild(el);
  }
  el.textContent = `
    @keyframes notification-freeze {
      0%   { opacity:1; box-shadow:${lo}; }
      9%   { opacity:1; box-shadow:${hi}; }
      18%  { opacity:1; box-shadow:${lo}; }
      27%  { opacity:1; box-shadow:${hi}; }
      36%  { opacity:1; box-shadow:${lo}; }
      45%  { opacity:1; box-shadow:${hi}; }
      54%  { opacity:1; box-shadow:${lo}; }
      63%  { opacity:1; box-shadow:${hi}; }
      72%  { opacity:1; box-shadow:${lo}; }
      81%  { opacity:1; box-shadow:${hi}; }
      92%  { opacity:0.15; box-shadow:${dim}; }
      100% { opacity:0; box-shadow:none; }
    }`;
}

function renderPill(sessions) {
  if (sessions.length === 0) {
    pillDot.className = "status-dot empty";
    pillText.textContent = "No sessions";
    pillCount.textContent = "";
    pill.dataset.state = "empty";
    pillGlow.dataset.state = "empty";
    return;
  }

  const dominant = dominantState(sessions);
  pillDot.className = `status-dot ${dominant}`;
  pill.dataset.state = dominant;

  // Notification: freeze aurora at current position, pulse glow in random aurora color
  if (dominant === "notification") {
    // Capture current animated values before removing aurora-flow/aurora-glow
    const computed = getComputedStyle(pillGlow);
    pillGlow.style.backgroundPosition = computed.backgroundPosition;
    injectFreezeKeyframe(computed.boxShadow || "");
  } else {
    // Clear frozen position so aurora-flow can resume
    pillGlow.style.backgroundPosition = "";
  }
  pillGlow.dataset.state = dominant;

  if (sessions.length === 1) {
    const s = sessions[0];
    const label = s.title || s.project;
    pillText.textContent = `${label} · ${s.state}`;
    pillCount.textContent = s.tool_name || "";
  } else {
    pillText.textContent = `${sessions.length} sessions`;
    pillCount.textContent = dominant;
  }
}

function agentBadge(session) {
  const meta = AGENT_META[session.agent] ?? {
    label: (session.agent_label || (session.agent || "?").slice(0, 2).toUpperCase()),
    color: session.agent_color || "#888",
  };
  return `<span class="agent-badge" style="background:${meta.color}" title="${escapeHtml(session.agent || "")}">${meta.label}</span>`;
}

function renderDashboard(sessions) {
  sessionCount.textContent = `${sessions.length} active`;

  if (sessions.length === 0) {
    sessionsList.innerHTML = '<div class="empty-state">No active sessions</div>';
    return;
  }

  sessionsList.innerHTML = sessions
    .map((s) => {
      const elapsed = formatElapsed(s.started_at);
      const title = s.title ? `<div class="session-title">${escapeHtml(s.title)}</div>` : "";
      const toolInfo = s.tool_name
        ? `<span class="session-tool">${escapeHtml(s.tool_name)}</span>`
        : "";
      const agentColor = (AGENT_META[s.agent] ?? { color: s.agent_color || "#888" }).color;
      return `
        <div class="session-card" style="--agent-color:${agentColor}">
          <div class="status-dot ${s.state}"></div>
          ${agentBadge(s)}
          <div class="session-info">
            <div class="session-project">${escapeHtml(s.project)}</div>
            ${title}
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

// ===== Polling Fallback =====

async function fetchState() {
  try {
    const res = await fetch(API_URL);
    const data = await res.json();
    handleStateUpdate(data.sessions || []);
  } catch {
    pillDot.className = "status-dot empty";
    pillText.textContent = "Backend offline";
    pillCount.textContent = "";
    pill.dataset.state = "empty";
    pillGlow.dataset.state = "empty";
    if (isExpanded) {
      sessionsList.innerHTML = '<div class="empty-state">Backend offline</div>';
    }
  }
}

function restartPolling() {
  stopPolling();
  pollTimer = setInterval(fetchState, POLL_FALLBACK);
  fetchState();
}

function stopPolling() {
  if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
}

// ===== Confetti =====

function triggerConfetti() {
  const canvas = document.getElementById("confettiCanvas");
  if (!canvas) return;
  const ctx = canvas.getContext("2d");
  canvas.width = canvas.parentElement.offsetWidth;
  canvas.height = canvas.parentElement.offsetHeight;
  canvas.style.display = "block";

  const colors = ["#4ade80", "#60a5fa", "#fb923c", "#c084fc", "#fbbf24", "#f87171"];
  const particles = [];
  for (let i = 0; i < 40; i++) {
    particles.push({
      x: canvas.width / 2 + (Math.random() - 0.5) * canvas.width * 0.6,
      y: -10,
      vx: (Math.random() - 0.5) * 4,
      vy: Math.random() * 2 + 1,
      size: Math.random() * 5 + 2,
      color: colors[Math.floor(Math.random() * colors.length)],
      rotation: Math.random() * 360,
      rotSpeed: (Math.random() - 0.5) * 10,
      life: 1,
    });
  }

  let frame = 0;
  function animate() {
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    let alive = false;
    for (const p of particles) {
      if (p.life <= 0) continue;
      alive = true;
      p.x += p.vx;
      p.y += p.vy;
      p.vy += 0.08;
      p.rotation += p.rotSpeed;
      p.life -= 0.012;

      ctx.save();
      ctx.translate(p.x, p.y);
      ctx.rotate((p.rotation * Math.PI) / 180);
      ctx.globalAlpha = Math.max(0, p.life);
      ctx.fillStyle = p.color;
      ctx.fillRect(-p.size / 2, -p.size / 2, p.size, p.size * 0.6);
      ctx.restore();
    }
    frame++;
    if (alive && frame < 120) {
      requestAnimationFrame(animate);
    } else {
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      canvas.style.display = "none";
    }
  }
  requestAnimationFrame(animate);
}

// ===== Init =====
connectWebSocket();
restartPolling(); // Start polling immediately, WebSocket will stop it once connected
