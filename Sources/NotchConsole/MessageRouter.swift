import Foundation
import UserNotifications

/// Routes WKScriptMessage payloads to appropriate handlers.
final class MessageRouter {
    private let soundManager: SoundManager
    private weak var controller: NotchController?

    init(soundManager: SoundManager) {
        self.soundManager = soundManager
    }

    func setController(_ controller: NotchController) {
        self.controller = controller
    }

    private var notificationPermissionRequested = false

    func requestNotificationPermission() {
        guard !notificationPermissionRequested else { return }
        notificationPermissionRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func deliverTimerNotification(_ payload: [String: Any]?) {
        let preset = payload?["preset"] as? String ?? "Timer"
        let content = UNMutableNotificationContent()
        content.title = "notchOS Timer"
        content.body = "\(preset) complete!"
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func handle(_ body: [String: Any]) {
        guard let type = body["type"] as? String else {
            // Legacy: support old action-based messages
            if let action = body["action"] as? String {
                switch action {
                case "expand": controller?.expand()
                case "collapse": controller?.collapse()
                default: break
                }
            }
            return
        }

        switch type {
        case "playSound":
            if let value = body["value"] as? String {
                soundManager.play(value)
            }
        case "toggleMute":
            soundManager.toggleMute()
        case "expand":
            controller?.expand()
        case "collapse":
            controller?.collapse()
        case "openSettingsWindow":
            controller?.settingsWindow.show()
        case "settingChanged":
            if let payload = body["value"] as? [String: Any],
               let key = payload["key"] as? String {
                controller?.applySetting(key: key, rawValue: payload["value"])
            }
        case "setSplit":
            if let value = body["value"] as? Bool {
                controller?.setSplit(value)
            }
        case "mediaPlayPause":
            controller?.nowPlayingMonitor?.sendCommand(NowPlayingMonitor.mrCommandTogglePlayPause)
        case "mediaNext":
            controller?.nowPlayingMonitor?.sendCommand(NowPlayingMonitor.mrCommandNextTrack)
        case "mediaPrevious":
            controller?.nowPlayingMonitor?.sendCommand(NowPlayingMonitor.mrCommandPreviousTrack)
        case "timerComplete":
            deliverTimerNotification(body["value"] as? [String: Any])
        case "jumpToTerminal":
            if let payload = body["value"] as? [String: Any] {
                TerminalJump.jump(
                    sessionId: payload["session_id"] as? String,
                    cwd: payload["cwd"] as? String
                )
            }
        default:
            break
        }
    }
}
