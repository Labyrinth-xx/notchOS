/**
 * Notification Module — shows permission requests and alerts with jump-to-terminal.
 *
 * Not a standalone activity — renders notification cards within the Claude tab
 * when a session is in notification/attention state.
 */

class NotificationModule extends NotchModule {
  get id() { return "notification"; }
  get tabLabel() { return "Alerts"; }

  renderPill(container, data) {
    // Notifications use the main pill's notification state (glow + color)
  }

  renderDashboard(container, data) {
    // Check if notifications are enabled
    const notifEnabled = data.settings ? data.settings.enableNotifications !== false : true;
    const sessions = data.sessions || [];
    const alerts = notifEnabled
      ? sessions.filter(
          (s) => s.state === "notification" || s.state === "attention" || s.state === "error"
        )
      : [];

    if (alerts.length === 0) {
      container.innerHTML = '<div class="empty-state">No alerts</div>';
      return;
    }

    container.innerHTML = alerts.map((s) => {
      const toolInfo = s.tool_name
        ? `<div class="notif-tool">${escapeHtml(s.tool_name)}</div>`
        : "";
      const stateLabel = s.state === "notification"
        ? "Needs attention"
        : s.state === "error"
        ? "Error"
        : "Attention";

      return `
        <div class="notif-card">
          <div class="status-dot ${s.state}"></div>
          <div class="notif-info">
            <div class="notif-project">${escapeHtml(s.project)}</div>
            <div class="notif-state">${stateLabel}</div>
            ${toolInfo}
          </div>
          <button class="notif-jump-btn"
            data-session-id="${escapeHtml(s.session_id)}"
            data-cwd="${escapeHtml(s.cwd || s.project || "")}">
            Jump
          </button>
        </div>
      `;
    }).join("");

    // Attach click handlers via dataset (avoids inline JS injection)
    for (const btn of container.querySelectorAll(".notif-jump-btn")) {
      btn.addEventListener("click", () => {
        notifySwift("jumpToTerminal", {
          session_id: btn.dataset.sessionId,
          cwd: btn.dataset.cwd,
        });
      });
    }
  }
}

registerModule(new NotificationModule());
