import Foundation

/// Centralized configuration constants for notchOS.
enum Config {
    static let backendHost = "127.0.0.1"
    static let backendPort = 23456

    static var backendBaseURL: String { "http://\(backendHost):\(backendPort)" }
    static var uiURL: URL {
        guard let url = URL(string: "\(backendBaseURL)/ui/index.html") else {
            fatalError("Invalid backend URL configuration")
        }
        return url
    }

    enum Timing {
        static let expandDwell: TimeInterval = 0.4
        static let collapseDelay: TimeInterval = 0.15
        static let expandDuration: TimeInterval = 0.25
        static let collapseDuration: TimeInterval = 0.2
        static let soundDebounce: TimeInterval = 3.0
    }

    enum Geometry {
        static let pillHeight: CGFloat = 32
        static let glowPad: CGFloat = 44
        static let wingWidth: CGFloat = 0
        static let hoverSlackDx: CGFloat = -20
        static let hoverSlackDy: CGFloat = -4
        static let expandedExtraWidth: CGFloat = 200
        static let expandedHeight: CGFloat = 260
        // Non-notch fallback
        static let fallbackCenterWidth: CGFloat = 220
        static let fallbackExpandedWidth: CGFloat = 380
        static let fallbackExpandedHeight: CGFloat = 240
        static let fallbackTopOffset: CGFloat = 6
    }

    enum Sound {
        static let volume: Float = 0.4
        static let map: [String: String] = [
            "complete": "/System/Library/Sounds/Glass.aiff",
            "error": "/System/Library/Sounds/Sosumi.aiff",
            "attention": "/System/Library/Sounds/Ping.aiff",
        ]
    }
}
