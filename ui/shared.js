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
};

function notifySwift(type, value) {
  try {
    window.webkit.messageHandlers.notch.postMessage({ type, value });
  } catch { /* Swift bridge not available */ }
}
