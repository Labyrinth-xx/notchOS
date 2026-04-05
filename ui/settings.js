/**
 * notchOS Settings Window — independent page running in its own NSWindow.
 * SETTINGS_KEY, DEFAULT_SETTINGS, notifySwift come from shared.js.
 */

let settings = { ...DEFAULT_SETTINGS };

function load() {
  try {
    const raw = localStorage.getItem(SETTINGS_KEY);
    if (raw) settings = { ...DEFAULT_SETTINGS, ...JSON.parse(raw) };
  } catch { /* use defaults */ }
  syncUI();
}

function save() {
  try { localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings)); } catch { /* ignore */ }
  notifySwift("settingsUpdated", {});
}

function syncUI() {
  const g = (id) => document.getElementById(id);
  g("s-detailedMode").checked      = settings.detailedMode;
  g("s-showAgentActivity").checked = settings.showAgentActivity;
  g("s-fontSize").value            = settings.fontSize;
  g("s-maxListHeight").value       = settings.maxListHeight;
  g("s-heightVal").textContent     = settings.maxListHeight + "px";
  g("s-hideInFullscreen").checked  = settings.hideInFullscreen;
  g("s-autoHideWhenIdle").checked  = settings.autoHideWhenIdle;
}

function initListeners() {
  const g = (id) => document.getElementById(id);

  g("s-detailedMode").addEventListener("change", (e) => {
    settings = { ...settings, detailedMode: e.target.checked };
    save();
  });

  g("s-showAgentActivity").addEventListener("change", (e) => {
    settings = { ...settings, showAgentActivity: e.target.checked };
    save();
  });

  g("s-fontSize").addEventListener("change", (e) => {
    settings = { ...settings, fontSize: e.target.value };
    save();
  });

  g("s-maxListHeight").addEventListener("input", (e) => {
    const val = parseInt(e.target.value, 10);
    g("s-heightVal").textContent = val + "px";
    settings = { ...settings, maxListHeight: val };
    save();
  });

  g("s-hideInFullscreen").addEventListener("change", (e) => {
    settings = { ...settings, hideInFullscreen: e.target.checked };
    save();
    notifySwift("settingChanged", { key: "hideInFullscreen", value: e.target.checked });
  });

  g("s-autoHideWhenIdle").addEventListener("change", (e) => {
    settings = { ...settings, autoHideWhenIdle: e.target.checked };
    save();
  });
}

load();
initListeners();
