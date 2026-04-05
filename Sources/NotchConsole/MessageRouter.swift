import Foundation

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
        default:
            break
        }
    }
}
