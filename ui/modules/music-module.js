/**
 * Music Module — Now Playing display in Dynamic Island.
 *
 * Data source: Swift NowPlayingMonitor → window.notchUpdateMusic()
 * Pill: album art thumbnail or music icon
 * Dashboard: album art, track/artist, progress bar
 */

class MusicModule extends NotchModule {
  get id() { return "music"; }
  get tabLabel() { return "Music"; }
  get bubbleIcon() { return "\u266B"; }

  renderPill(container, data) {
    // Music pill is rendered in the left bubble, not the main pill
  }

  renderDashboard(container, data) {
    const music = data.music;
    if (!music) {
      container.innerHTML = '<div class="empty-state">No music playing</div>';
      return;
    }

    const progress = music.duration > 0
      ? Math.min(100, (music.elapsed / music.duration) * 100)
      : 0;

    const artworkHtml = music.artwork
      ? `<img class="music-artwork" src="${music.artwork}" alt="Album art">`
      : '<div class="music-artwork music-artwork-placeholder">\u266B</div>';

    container.innerHTML = `
      <div class="music-card">
        ${artworkHtml}
        <div class="music-info">
          <div class="music-title">${escapeHtml(music.title)}</div>
          <div class="music-artist">${escapeHtml(music.artist)}</div>
          ${music.album ? `<div class="music-album">${escapeHtml(music.album)}</div>` : ""}
        </div>
        <div class="music-state">${music.isPlaying ? "\u25B6" : "\u23F8"}</div>
      </div>
      <div class="music-progress-bar">
        <div class="music-progress-fill" style="width: ${progress}%"></div>
      </div>
      <div class="music-times">
        <span>${formatMusicTime(music.elapsed)}</span>
        <span>${formatMusicTime(music.duration)}</span>
      </div>
      <div class="music-controls">
        <button class="music-btn" onclick="notifySwift('mediaPrevious','')">
          \u23EE
        </button>
        <button class="music-btn music-btn-play" onclick="notifySwift('mediaPlayPause','')">
          ${music.isPlaying ? "\u23F8" : "\u25B6\uFE0F"}
        </button>
        <button class="music-btn" onclick="notifySwift('mediaNext','')">
          \u23ED
        </button>
      </div>
    `;
  }
}

function formatMusicTime(seconds) {
  if (!seconds || seconds <= 0) return "0:00";
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s.toString().padStart(2, "0")}`;
}

// Bridge: receive music data from Swift NowPlayingMonitor
window.notchUpdateMusic = function (data) {
  // Check if music module is enabled in settings
  try {
    const raw = localStorage.getItem(SETTINGS_KEY);
    if (raw) {
      const s = JSON.parse(raw);
      if (s.enableMusic === false) {
        activityManager.remove("music");
        window._latestMusicData = null;
        return;
      }
    }
  } catch { /* use default (enabled) */ }

  if (data) {
    activityManager.update(
      "music",
      "music",
      data,
      data.isPlaying ? 30 : 60  // ACTIVITY_PRIORITIES.music_playing : music_paused
    );
  } else {
    activityManager.remove("music");
  }

  // Store latest music data for dashboard rendering
  window._latestMusicData = data;
};

registerModule(new MusicModule());
