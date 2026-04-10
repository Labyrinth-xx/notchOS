/**
 * notchOS Content Module System
 *
 * Base class and registry for dynamic island content modules.
 * Each module handles rendering for a specific content type
 * (session status, permission dialog, notification bubble, etc.)
 */

class NotchModule {
  /** Unique module identifier (must match backend content_module field). */
  get id() {
    throw new Error("NotchModule.id must be overridden");
  }

  /** Label shown in the tab bar when multiple activities are active. */
  get tabLabel() {
    return this.id;
  }

  /** Icon shown in the left bubble when this is the secondary activity. */
  get bubbleIcon() {
    return "\u25CF";
  }

  /**
   * Render content in pill (collapsed) mode.
   * @param {HTMLElement} container - The pill center element
   * @param {object} data - Module-specific data from backend
   */
  renderPill(container, data) {}

  /**
   * Render content in dashboard (expanded) mode.
   * @param {HTMLElement} container - The sessions list element
   * @param {object} data - Module-specific data from backend
   */
  renderDashboard(container, data) {}

  /**
   * Called when this module becomes the active content module.
   * @param {object} data - Activation payload from backend
   */
  onActivate(data) {}

  /**
   * Called when this module is deactivated (another module takes over).
   */
  onDeactivate() {}
}

// Module registry
const moduleRegistry = new Map();

function registerModule(module) {
  if (!(module instanceof NotchModule)) {
    throw new Error("Module must extend NotchModule");
  }
  moduleRegistry.set(module.id, module);
}

function getModule(id) {
  return moduleRegistry.get(id);
}

function listModules() {
  return Array.from(moduleRegistry.keys());
}

// Active module tracking
let activeModuleId = "session_status";

function getActiveModule() {
  return moduleRegistry.get(activeModuleId);
}

function setActiveModule(moduleId) {
  const prev = moduleRegistry.get(activeModuleId);
  if (prev && prev.onDeactivate) prev.onDeactivate();

  activeModuleId = moduleId;

  const next = moduleRegistry.get(moduleId);
  if (next && next.onActivate) next.onActivate({});
}
