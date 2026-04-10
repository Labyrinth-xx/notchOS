/**
 * notchOS shared utilities — loaded by both index.html and settings.html.
 */

const SETTINGS_KEY = "notch-settings";
const DEFAULT_SETTINGS = {
  detailedMode: true,
  showAgentActivity: false,
  fontSize: "medium",
  maxListHeight: 180,
  hideInFullscreen: false,
  autoHideWhenIdle: false,
  enableMusic: true,
  enableTimer: true,
  enableNotifications: true,
};

function notifySwift(type, value) {
  try {
    window.webkit.messageHandlers.notch.postMessage({ type, value });
  } catch { /* Swift bridge not available */ }
}

// Shared utility: check if a module is enabled in settings (cached)
let _settingsCache = null;

function _loadSettingsCache() {
  try {
    const raw = localStorage.getItem(SETTINGS_KEY);
    _settingsCache = raw ? { ...DEFAULT_SETTINGS, ...JSON.parse(raw) } : { ...DEFAULT_SETTINGS };
  } catch { _settingsCache = { ...DEFAULT_SETTINGS }; }
}

function isModuleEnabled(settingKey) {
  if (!_settingsCache) _loadSettingsCache();
  return _settingsCache[settingKey] !== false;
}

function invalidateSettingsCache() {
  _settingsCache = null;
}

// Shared utilities
function escapeHtml(str) {
  const el = document.createElement("span");
  el.textContent = str;
  return el.innerHTML;
}

function formatElapsed(startedAt) {
  const seconds = Math.floor(Date.now() / 1000 - startedAt);
  if (seconds < 60) return `${seconds}s`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.floor(minutes / 60);
  return `${hours}h ${minutes % 60}m`;
}

function formatMusicTime(seconds) {
  if (!seconds || seconds <= 0) return "0:00";
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s.toString().padStart(2, "0")}`;
}
