/**
 * notchOS Activity Manager
 *
 * Manages multiple concurrent activities (Claude sessions, music, timer, etc.)
 * and determines layout: which is primary (right pill), which is secondary (left bubble).
 *
 * Priority rules (lower number = higher priority):
 *   Claude active (thinking/working/error/juggling)  → 10
 *   Timer running                                     → 20
 *   Music playing                                     → 30
 *   Claude idle                                       → 40
 *   Timer paused                                      → 50
 *   Music paused                                      → 60
 */

const ACTIVITY_PRIORITIES = {
  claude_active: 10,
  timer_running: 20,
  music_playing: 30,
  claude_idle: 40,
  timer_paused: 50,
  music_paused: 60,
};

// States that count as "active" for Claude sessions
const CLAUDE_ACTIVE_STATES = new Set([
  "thinking", "working", "error", "attention",
  "notification", "juggling", "sweeping", "carrying",
]);

class ActivityManager {
  constructor() {
    /** @type {Map<string, {type: string, moduleId: string, data: object, priority: number}>} */
    this._activities = new Map();
    this._listeners = [];
  }

  /**
   * Update an activity. Creates it if new, updates if existing.
   * @param {string} type - "claude" | "music" | "timer"
   * @param {string} moduleId - corresponding module ID
   * @param {object} data - activity-specific data
   * @param {number} priority - dynamic priority value
   */
  update(type, moduleId, data, priority) {
    this._activities.set(type, { type, moduleId, data, priority });
    this._notify();
  }

  /**
   * Remove an activity (e.g., music stopped, timer completed).
   * @param {string} type
   */
  remove(type) {
    if (this._activities.delete(type)) {
      this._notify();
    }
  }

  /**
   * Update Claude sessions from WebSocket data.
   * Automatically computes priority based on session states.
   * @param {Array} sessions - session objects from backend
   */
  updateClaude(sessions) {
    if (sessions.length === 0) {
      this.remove("claude");
      return;
    }

    const hasActive = sessions.some((s) => CLAUDE_ACTIVE_STATES.has(s.state));
    const priority = hasActive ? ACTIVITY_PRIORITIES.claude_active : ACTIVITY_PRIORITIES.claude_idle;
    this.update("claude", "session_status", { sessions }, priority);
  }

  /**
   * Get the current layout: primary + optional secondary activity.
   * @returns {{ primary: object|null, secondary: object|null, all: object[] }}
   */
  getLayout() {
    const sorted = Array.from(this._activities.values())
      .sort((a, b) => a.priority - b.priority);

    return {
      primary: sorted[0] || null,
      secondary: sorted[1] || null,
      all: sorted,
    };
  }

  /**
   * Check if multiple activities are active (triggers split-pill mode).
   * @returns {boolean}
   */
  get isSplit() {
    return this._activities.size >= 2;
  }

  /**
   * Get activity by type.
   * @param {string} type
   * @returns {object|undefined}
   */
  get(type) {
    return this._activities.get(type);
  }

  /**
   * Register a listener for activity changes.
   * @param {function} fn - called with getLayout() result
   */
  onChange(fn) {
    this._listeners.push(fn);
  }

  _notify() {
    const layout = this.getLayout();
    for (const fn of this._listeners) {
      try { fn(layout); } catch { /* listener error */ }
    }
  }
}

// Global singleton
const activityManager = new ActivityManager();
