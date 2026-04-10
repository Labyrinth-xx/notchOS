/**
 * notchOS — Notch UI
 * WebSocket-first with polling fallback for session state.
 * State definitions loaded from shared/states.json (single source of truth).
 */

const WS_URL = "ws://127.0.0.1:23456/ws";
const API_URL = "http://127.0.0.1:23456/api/state";
const STATES_URL = "/shared/states.json";

// Agent identity map — mirrors backend AGENT_META.
const AGENT_META = {
  "claude-code": { label: "CC", color: "#F59E0B" },
};
const POLL_FALLBACK = 5000;
const RECONNECT_DELAY = 3000;

let isExpanded = false;
let pollTimer = null;
let ws = null;
let wsConnected = false;

// State configuration loaded from states.json
let statesConfig = null;
let statePriority = [];  // sorted state names by priority (ascending = higher priority first)

// Track previous states per session for transition detection
const previousStates = new Map();

// ===== Settings =====
// SETTINGS_KEY, DEFAULT_SETTINGS, notifySwift defined in shared.js

let settings = { ...DEFAULT_SETTINGS };
let autoHideTimer = null;
let lastStateData = null;

function loadSettings() {
  try {
    const stored = localStorage.getItem(SETTINGS_KEY);
    if (stored) settings = { ...DEFAULT_SETTINGS, ...JSON.parse(stored) };
  } catch { /* use defaults on error */ }
  applySettings();
}

function applySettings() {
  const fontMap = { small: "11px", medium: "12px", large: "13px" };
  document.documentElement.style.setProperty("--font-size-base", fontMap[settings.fontSize] || "12px");
  const list = document.getElementById("sessionsList");
  if (list) list.style.maxHeight = settings.maxListHeight + "px";
  notifySwift("settingChanged", { key: "hideInFullscreen", value: settings.hideInFullscreen });
}

window.toggleSettingsPanel = function () {
  notifySwift("openSettingsWindow", "");
};

// Called by Swift after settings window saves — re-read localStorage and re-render
window.reloadSettings = function () {
  loadSettings();
  if (lastStateData) handleStateUpdate(lastStateData);
};

function scheduleAutoHide() {
  if (autoHideTimer !== null) return;
  autoHideTimer = setTimeout(() => {
    autoHideTimer = null;
    if (isExpanded && settings.autoHideWhenIdle) notifySwift("collapse", "");
  }, 10000);
}

function cancelAutoHide() {
  if (autoHideTimer !== null) {
    clearTimeout(autoHideTimer);
    autoHideTimer = null;
  }
}

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

// ===== State Config Loading =====

async function loadStatesConfig() {
  try {
    const res = await fetch(STATES_URL);
    statesConfig = await res.json();

    // Build priority-sorted state list (lower number = higher priority)
    statePriority = Object.entries(statesConfig.states)
      .sort(([, a], [, b]) => a.priority - b.priority)
      .map(([name]) => name);

    // Inject dynamic CSS for state-driven styles
    injectStateStyles();
  } catch {
    // Fallback: hardcoded priority if config fails to load
    statePriority = [
      "error", "attention", "notification",
      "thinking", "working", "juggling",
      "sweeping", "carrying", "idle", "sleeping",
    ];
  }
}

function injectStateStyles() {
  if (!statesConfig) return;

  let css = "";
  const states = statesConfig.states;
  const glowAnimations = statesConfig.glow_animations;

  for (const [name, def] of Object.entries(states)) {
    // Status dot styles
    const dotAnim = def.dot_animation ? `animation: ${def.dot_animation};` : "";
    const dotOpacity = def.dot_opacity !== 1 ? `opacity: ${def.dot_opacity};` : "";
    css += `.status-dot.${name} { background: ${def.color}; ${dotAnim} ${dotOpacity} }\n`;

    // Session state text color in dashboard
    css += `.session-state.${name} { color: ${def.color}; }\n`;

    // Pill glow per-state rules
    const glowType = def.glow_type;
    if (glowType && glowAnimations[glowType]) {
      const glow = glowAnimations[glowType];
      const bgRule = glow.background ? `background: ${glow.background};` : "";
      css += `#pillGlow[data-state="${name}"] { opacity: 1; ${bgRule} animation: ${glow.animation}; }\n`;
    }
  }

  let el = document.getElementById("state-styles");
  if (!el) {
    el = document.createElement("style");
    el.id = "state-styles";
    document.head.appendChild(el);
  }
  el.textContent = css;
}

// ===== Swift Bridge =====

// Called by Swift via evaluateJavaScript
window.notchSetExpanded = function (expanded) {
  isExpanded = expanded;
  pill.classList.toggle("hidden", expanded);
  pillGlow.classList.toggle("hidden", expanded);
  // Hide left bubble when expanded (dashboard shows everything)
  const bubbleLeft = document.getElementById("bubbleLeft");
  if (bubbleLeft) bubbleLeft.classList.toggle("visible", false);
  dashboard.classList.toggle("visible", expanded);
  if (!wsConnected) restartPolling();
};

// Called by Swift when split mode changes
window.notchSetSplit = function (split) {
  const bubbleLeft = document.getElementById("bubbleLeft");
  if (bubbleLeft && !isExpanded) {
    bubbleLeft.classList.toggle("visible", split);
  }
  // Update tab bar visibility
  updateTabBar();
};

// Tab bar management
let activeTab = "claude";

function updateTabBar() {
  const tabBar = document.getElementById("tabBar");
  if (!tabBar) return;

  const layout = activityManager.getLayout();
  const hasTabs = layout.all.length >= 2;
  tabBar.classList.toggle("visible", hasTabs);

  if (!hasTabs) {
    // Single activity: show claude pane, hide tab bar
    activateTab("claude");
    return;
  }

  // Build tab buttons from active activities
  const tabNames = { claude: "Claude", music: "Music", timer: "Timer" };
  tabBar.innerHTML = layout.all.map((a) => {
    const label = tabNames[a.type] || a.type;
    const isActive = activeTab === a.type ? " active" : "";
    return `<button class="tab-btn${isActive}" data-tab="${a.type}">${label}</button>`;
  }).join("");

  // Attach click handlers
  for (const btn of tabBar.querySelectorAll(".tab-btn")) {
    btn.addEventListener("click", () => activateTab(btn.dataset.tab));
  }
}

function activateTab(tabId) {
  activeTab = tabId;
  // Update button states
  const tabBar = document.getElementById("tabBar");
  if (tabBar) {
    for (const btn of tabBar.querySelectorAll(".tab-btn")) {
      btn.classList.toggle("active", btn.dataset.tab === tabId);
    }
  }
  // Ensure the claude pane is always present; other panes created dynamically
  const tabContent = document.getElementById("tabContent");
  if (!tabContent) return;

  // Show/hide panes
  for (const pane of tabContent.querySelectorAll(".tab-pane")) {
    pane.classList.toggle("active", pane.id === `pane-${tabId}`);
  }

  // Create pane if it doesn't exist
  if (!document.getElementById(`pane-${tabId}`)) {
    const pane = document.createElement("div");
    pane.className = "tab-pane active";
    pane.id = `pane-${tabId}`;
    tabContent.appendChild(pane);
  }
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
  lastStateData = sessions;
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

  // Feed Claude sessions into ActivityManager
  activityManager.updateClaude(sessions);

  // Auto-hide when no active sessions
  if (settings.autoHideWhenIdle && isExpanded) {
    const allIdle = sessions.length === 0
      || sessions.every((s) => s.state === "idle" || s.state === "sleeping");
    if (allIdle) {
      scheduleAutoHide();
    } else {
      cancelAutoHide();
    }
  }

  renderPill(sessions);
  if (isExpanded) renderDashboard(sessions);
}

// Sound + confetti trigger on state transition
function onStateTransition(sessionId, fromState, toState) {
  if (!statesConfig) {
    // Fallback: hardcoded rules
    onStateTransitionFallback(fromState, toState);
    return;
  }

  const sounds = statesConfig.sounds;
  for (const [soundName, rule] of Object.entries(sounds)) {
    const fromMatch = rule.from.includes("*") || rule.from.includes(fromState);
    const toMatch = rule.to.includes(toState);
    if (fromMatch && toMatch) {
      notifySwift("playSound", soundName);
      if (soundName === "complete" && isExpanded) triggerConfetti();
    }
  }
}

function onStateTransitionFallback(fromState, toState) {
  const workingStates = new Set(["working", "thinking", "juggling"]);
  const doneStates = new Set(["idle", "sleeping", "attention"]);

  if (workingStates.has(fromState) && doneStates.has(toState)) {
    notifySwift("playSound", "complete");
    if (isExpanded) triggerConfetti();
  } else if (toState === "notification") {
    notifySwift("playSound", "attention");
  }
}

// notifySwift defined in shared.js

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
  for (const state of statePriority) {
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
  const dominant = sessions.length > 0 ? dominantState(sessions) : "empty";

  // Update pill + glow state attributes (shared across all modules)
  pill.dataset.state = dominant;
  pillGlow.dataset.state = dominant;

  // Notification: freeze aurora at current position
  if (dominant === "notification") {
    const computed = getComputedStyle(pillGlow);
    pillGlow.style.backgroundPosition = computed.backgroundPosition;
    injectFreezeKeyframe(computed.boxShadow || "");
  } else {
    pillGlow.style.backgroundPosition = "";
  }

  // Delegate content rendering to active module
  const mod = getActiveModule();
  if (mod) {
    const pillCenter = pill.querySelector(".pill-center");
    mod.renderPill(pillCenter, { sessions, dominant, settings, statesConfig });
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
  // Render the active tab's content
  const tabContent = document.getElementById("tabContent");
  if (!tabContent) return;

  // Always render claude pane (session status)
  const claudePane = document.getElementById("pane-claude");
  if (claudePane) {
    const claudeMod = getModule("session_status");
    if (claudeMod) {
      const list = claudePane.querySelector(".sessions-list") || claudePane;
      claudeMod.renderDashboard(list, { sessions, settings });
    }
  }

  // Render music pane if it exists and is active
  const musicPane = document.getElementById("pane-music");
  if (musicPane) {
    const musicMod = getModule("music");
    if (musicMod) {
      musicMod.renderDashboard(musicPane, { sessions, settings, music: window._latestMusicData });
    }
  }

  // Render timer pane if it exists and is active
  const timerPane = document.getElementById("pane-timer");
  if (timerPane) {
    const timerMod = getModule("timer");
    if (timerMod) {
      timerMod.renderDashboard(timerPane, { sessions, settings, timer: {} });
    }
  }
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

// Activity manager: notify Swift of split mode changes and update UI
activityManager.onChange((layout) => {
  const shouldSplit = layout.all.length >= 2;
  notifySwift("setSplit", shouldSplit);

  // Update left bubble content with secondary activity
  const bubbleLeft = document.getElementById("bubbleLeft");
  const bubbleIcon = document.getElementById("bubbleLeftIcon");
  if (bubbleLeft && bubbleIcon && layout.secondary) {
    const icons = { music: "\u266B", timer: "\u23F1", claude: "\u25CF" };
    bubbleIcon.textContent = icons[layout.secondary.type] || "\u25CF";
  }

  updateTabBar();
});

// Load state config + settings, then connect
loadStatesConfig().then(() => {
  loadSettings();
  connectWebSocket();
  restartPolling();
});
