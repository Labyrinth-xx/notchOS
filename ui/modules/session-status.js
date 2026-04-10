/**
 * Session Status Module — the default content module.
 *
 * Renders Claude Code session status in pill (collapsed) and dashboard (expanded) views.
 * Extracted from app.js to activate the module system.
 */

class SessionStatusModule extends NotchModule {
  get id() {
    return "session_status";
  }

  get tabLabel() {
    return "Claude";
  }

  get bubbleIcon() {
    return "\u25CF";
  }

  /**
   * Render pill (collapsed) view.
   * @param {HTMLElement} container - pill-center element
   * @param {object} data - { sessions, dominant, settings, statesConfig }
   */
  renderPill(container, data) {
    const { sessions, dominant, settings } = data;
    const pillDot = container.querySelector(".status-dot");
    const pillText = container.querySelector(".pill-text");
    const pillCount = container.querySelector(".pill-count");

    if (sessions.length === 0) {
      pillDot.className = "status-dot empty";
      pillText.textContent = "No sessions";
      pillCount.textContent = "";
      return;
    }

    pillDot.className = `status-dot ${dominant}`;

    if (sessions.length === 1) {
      const s = sessions[0];
      const label = s.title || s.project;
      if (settings.detailedMode) {
        pillText.textContent = `${label} \u00b7 ${s.state}`;
        pillCount.textContent = s.tool_name || "";
      } else {
        pillText.textContent = label;
        pillCount.textContent = "";
      }
    } else {
      pillText.textContent = `${sessions.length} sessions`;
      pillCount.textContent = settings.detailedMode ? dominant : "";
    }
  }

  /**
   * Render dashboard (expanded) view.
   * @param {HTMLElement} container - sessions-list element
   * @param {object} data - { sessions, settings }
   */
  renderDashboard(container, data) {
    const { sessions, settings } = data;
    const sessionCount = document.getElementById("sessionCount");
    if (sessionCount) sessionCount.textContent = `${sessions.length} active`;

    if (sessions.length === 0) {
      container.innerHTML = '<div class="empty-state">No active sessions</div>';
      return;
    }

    container.innerHTML = sessions
      .map((s) => {
        const elapsed = formatElapsed(s.started_at);
        const title = s.title
          ? `<div class="session-title">${escapeHtml(s.title)}</div>`
          : "";
        const toolInfo = s.tool_name
          ? `<span class="session-tool">${escapeHtml(s.tool_name)}</span>`
          : "";
        const activityRow =
          settings.showAgentActivity && s.tool_name
            ? `<div class="activity-row"><span class="activity-dot"></span><span class="activity-label">${escapeHtml(s.tool_name)}</span></div>`
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
                ${settings.showAgentActivity ? "" : toolInfo}
              </div>
              ${activityRow}
            </div>
            <span class="session-time">${elapsed}</span>
          </div>
        `;
      })
      .join("");
  }
}

// Auto-register
registerModule(new SessionStatusModule());
