/**
 * Timer/Pomodoro Module — built-in countdown timer.
 *
 * State: idle → running → paused → running → completed
 * Persisted to localStorage so timer survives page reload.
 * Completion notification sent to Swift via postMessage.
 */

const TIMER_STORAGE_KEY = "notch-timer";
const TIMER_PRESETS = [
  { label: "25m", seconds: 25 * 60, name: "Work" },
  { label: "5m", seconds: 5 * 60, name: "Break" },
  { label: "15m", seconds: 15 * 60, name: "Long Break" },
  { label: "1m", seconds: 60, name: "Test" },
];

class TimerModule extends NotchModule {
  constructor() {
    super();
    this.state = "idle"; // idle | running | paused | completed
    this.totalSeconds = TIMER_PRESETS[0].seconds;
    this.remaining = this.totalSeconds;
    this.startedAt = null;   // timestamp when current run started
    this.pausedRemaining = null;
    this._resumeBase = null; // remaining seconds at the moment of start/resume
    this.presetIndex = 0;
    this.pomodoroCount = 0;
    this._interval = null;
    this._restore();
  }

  get id() { return "timer"; }
  get tabLabel() { return "Timer"; }
  get bubbleIcon() { return "\u23F1"; }

  // --- State management ---

  start() {
    if (this.state === "completed") this.reset();
    this.state = "running";
    this.startedAt = Date.now();
    this._resumeBase = this.remaining;
    this.pausedRemaining = null;
    this._startTick();
    this._save();
    this._updateActivity();
  }

  pause() {
    if (this.state !== "running") return;
    this.state = "paused";
    this.pausedRemaining = this.remaining;
    this._stopTick();
    this._save();
    this._updateActivity();
  }

  resume() {
    if (this.state !== "paused") return;
    this.state = "running";
    this.startedAt = Date.now();
    this._resumeBase = this.pausedRemaining;
    this.remaining = this.pausedRemaining;
    this.pausedRemaining = null;
    this._startTick();
    this._save();
    this._updateActivity();
  }

  reset() {
    this._stopTick();
    this.state = "idle";
    this.remaining = this.totalSeconds;
    this.startedAt = null;
    this.pausedRemaining = null;
    this._save();
    activityManager.remove("timer");
  }

  setPreset(index) {
    if (this.state === "running") return;
    this.presetIndex = index;
    this.totalSeconds = TIMER_PRESETS[index].seconds;
    this.remaining = this.totalSeconds;
    this.state = "idle";
    this._save();
  }

  _complete() {
    this._stopTick();
    this.state = "completed";
    this.remaining = 0;
    this.pomodoroCount++;
    this._save();
    // Notify Swift for macOS notification
    notifySwift("timerComplete", {
      preset: TIMER_PRESETS[this.presetIndex].name,
      count: this.pomodoroCount,
    });
    this._updateActivity();
  }

  _startTick() {
    this._stopTick();
    this._interval = setInterval(() => this._tick(), 1000);
  }

  _stopTick() {
    if (this._interval) {
      clearInterval(this._interval);
      this._interval = null;
    }
  }

  _tick() {
    if (this.state !== "running" || !this.startedAt) return;
    const elapsed = (Date.now() - this.startedAt) / 1000;
    const base = this._resumeBase ?? this.totalSeconds;
    this.remaining = Math.max(0, base - elapsed);

    if (this.remaining <= 0) {
      this._complete();
    }
    this._updateActivity();
  }

  _updateActivity() {
    if (this.state === "idle") {
      activityManager.remove("timer");
      return;
    }

    if (!isModuleEnabled("enableTimer")) {
      activityManager.remove("timer");
      return;
    }

    const priority = this.state === "running"
      ? ACTIVITY_PRIORITIES.timer_running
      : ACTIVITY_PRIORITIES.timer_paused;
    activityManager.update("timer", "timer", {
      state: this.state,
      remaining: this.remaining,
      total: this.totalSeconds,
      preset: TIMER_PRESETS[this.presetIndex].name,
      pomodoroCount: this.pomodoroCount,
    }, priority);
  }

  // --- Persistence ---

  _save() {
    try {
      localStorage.setItem(TIMER_STORAGE_KEY, JSON.stringify({
        state: this.state,
        totalSeconds: this.totalSeconds,
        remaining: this.remaining,
        startedAt: this.startedAt,
        pausedRemaining: this.pausedRemaining,
        _resumeBase: this._resumeBase,
        presetIndex: this.presetIndex,
        pomodoroCount: this.pomodoroCount,
      }));
    } catch { /* storage full */ }
  }

  _restore() {
    try {
      const raw = localStorage.getItem(TIMER_STORAGE_KEY);
      if (!raw) return;
      const d = JSON.parse(raw);
      this.totalSeconds = d.totalSeconds || TIMER_PRESETS[0].seconds;
      this.presetIndex = d.presetIndex || 0;
      this.pomodoroCount = d.pomodoroCount || 0;

      if (d.state === "running" && d.startedAt) {
        // Recalculate remaining based on how long we were away
        const base = d._resumeBase ?? d.totalSeconds;
        const elapsed = (Date.now() - d.startedAt) / 1000;
        this.remaining = Math.max(0, base - elapsed);
        if (this.remaining > 0) {
          this.state = "running";
          this.startedAt = d.startedAt;
          this._resumeBase = base;
          this._startTick();
          this._updateActivity();
        } else {
          this._complete();
        }
      } else if (d.state === "paused") {
        this.state = "paused";
        this.remaining = d.pausedRemaining || d.remaining || this.totalSeconds;
        this.pausedRemaining = this.remaining;
        this._updateActivity();
      } else {
        this.remaining = d.remaining || this.totalSeconds;
      }
    } catch { /* corrupted storage */ }
  }

  // --- Rendering ---

  renderPill(container, data) {
    // Timer pill rendered in left bubble, not main pill
  }

  renderDashboard(container, data) {
    const timer = data.timer || {};
    const remaining = this.remaining;
    const total = this.totalSeconds;
    const progress = total > 0 ? ((total - remaining) / total) * 100 : 0;

    const minutes = Math.floor(remaining / 60);
    const seconds = Math.floor(remaining % 60);
    const timeStr = `${minutes}:${seconds.toString().padStart(2, "0")}`;

    // Color classes
    let colorClass = "";
    let progressColor = "var(--green)";
    if (remaining < 60 && this.state === "running") {
      colorClass = "critical";
      progressColor = "var(--red)";
    } else if (remaining < 300 && this.state === "running") {
      colorClass = "warning";
      progressColor = "var(--yellow)";
    }

    const stateLabel = this.state === "completed"
      ? "Done!"
      : TIMER_PRESETS[this.presetIndex].name;

    const presetsHtml = TIMER_PRESETS.map((p, i) =>
      `<button class="timer-preset${i === this.presetIndex ? " active" : ""}"
              onclick="timerModule.setPreset(${i})">${p.label}</button>`
    ).join("");

    let controlsHtml = "";
    if (this.state === "idle") {
      controlsHtml = `<button class="timer-btn timer-btn-primary" onclick="timerModule.start()">Start</button>`;
    } else if (this.state === "running") {
      controlsHtml = `<button class="timer-btn" onclick="timerModule.pause()">Pause</button>
        <button class="timer-btn" onclick="timerModule.reset()">Reset</button>`;
    } else if (this.state === "paused") {
      controlsHtml = `<button class="timer-btn timer-btn-primary" onclick="timerModule.resume()">Resume</button>
        <button class="timer-btn" onclick="timerModule.reset()">Reset</button>`;
    } else if (this.state === "completed") {
      controlsHtml = `<button class="timer-btn timer-btn-primary" onclick="timerModule.reset()">Reset</button>`;
    }

    container.innerHTML = `
      <div class="timer-card">
        <div class="timer-label">${escapeHtml(stateLabel)}</div>
        <div class="timer-display ${colorClass}">${timeStr}</div>
        <div class="timer-progress">
          <div class="timer-progress-fill" style="width: ${progress}%; background: ${progressColor}"></div>
        </div>
        <div class="timer-controls">${controlsHtml}</div>
        <div class="timer-presets">${presetsHtml}</div>
        ${this.pomodoroCount > 0 ? `<div class="timer-session-count">${this.pomodoroCount} pomodoro${this.pomodoroCount > 1 ? "s" : ""} completed</div>` : ""}
      </div>
    `;
  }
}

// Global reference for onclick handlers
const timerModule = new TimerModule();
registerModule(timerModule);
