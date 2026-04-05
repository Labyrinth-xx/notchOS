import AppKit
import WebKit

/// Independent settings window — separate NSWindow with its own WebView.
/// Opened via the ⚙ button in the notch dashboard.
/// WebView is lazy-loaded on first show() to avoid startup cost.
final class SettingsWindowController: NSObject {

    weak var notchController: NotchController?

    private let window: NSWindow
    private var webView: WKWebView?

    override init() {
        self.window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        self.window.title = "notchOS 设置"
        self.window.isReleasedWhenClosed = false
        self.window.titlebarAppearsTransparent = true
        self.window.backgroundColor = NSColor(calibratedWhite: 0.09, alpha: 1.0)

        super.init()
    }

    private func ensureWebViewLoaded() {
        guard webView == nil else { return }

        let config = WKWebViewConfiguration()
        let userContent = WKUserContentController()
        config.userContentController = userContent

        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 380, height: 480), configuration: config)
        self.webView = wv
        self.window.contentView = wv

        userContent.add(self, name: "notch")
        wv.load(URLRequest(url: Config.settingsURL))
    }

    func show() {
        ensureWebViewLoaded()
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        window.orderOut(nil)
    }
}

extension SettingsWindowController: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }
        switch type {
        case "closeSettings":
            hide()
        case "settingsUpdated":
            // Reload main dashboard settings after any change
            notchController?.reloadSettingsInDashboard()
        case "settingChanged":
            // Apply Swift-side settings (e.g. hideInFullscreen → collectionBehavior)
            // settingsUpdated handles dashboard reload separately
            if let payload = body["value"] as? [String: Any],
               let key = payload["key"] as? String {
                notchController?.applySetting(key: key, rawValue: payload["value"])
            }
        default:
            break
        }
    }
}
