/**
 * Session Status Module — the default content module.
 *
 * Renders session status cards in the dashboard.
 * This is the existing rendering behavior wrapped as a module.
 * Currently, all rendering is still handled by app.js directly.
 * This file serves as the registration point and future extraction target.
 */

class SessionStatusModule extends NotchModule {
  get id() {
    return "session_status";
  }

  // Rendering is currently handled by app.js renderPill/renderDashboard.
  // Future: extract those functions here for full encapsulation.
}

// Auto-register
registerModule(new SessionStatusModule());
