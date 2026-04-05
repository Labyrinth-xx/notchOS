import AppKit

/// Manages sound playback with per-category debounce and mute support.
final class SoundManager {
    private var isMuted = false
    private var lastSoundTime: [String: Date] = [:]

    var muted: Bool { isMuted }

    func toggleMute() {
        isMuted = !isMuted
    }

    func play(_ name: String) {
        guard !isMuted else { return }

        // Debounce: same sound category at most once per interval
        let now = Date()
        if let last = lastSoundTime[name], now.timeIntervalSince(last) < Config.Timing.soundDebounce {
            return
        }
        lastSoundTime[name] = now

        guard let path = Config.Sound.map[name],
              let sound = NSSound(contentsOfFile: path, byReference: true) else { return }
        sound.volume = Config.Sound.volume
        sound.play()
    }
}
