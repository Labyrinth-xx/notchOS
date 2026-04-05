import AppKit
import WebKit

/// Manages the overlay panel, WebView, hover interactions, and delegates sound/messages.
final class NotchController: NSObject, WKScriptMessageHandler {
    let panel: OverlayPanel
    let webView: WKWebView
    let geometry: NotchGeometry
    let soundManager: SoundManager
    let messageRouter: MessageRouter

    private var isExpanded = false
    private var mouseMonitor: Any?
    private var collapseTimer: Timer?
    private var expandTimer: Timer?

    override init() {
        self.geometry = NotchGeometry.detect()
        self.panel = OverlayPanel()
        self.soundManager = SoundManager()
        self.messageRouter = MessageRouter(soundManager: soundManager)

        // Configure WKWebView
        let config = WKWebViewConfiguration()
        let userContent = WKUserContentController()
        config.userContentController = userContent
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        self.webView = WKWebView(frame: .zero, configuration: config)
        self.webView.setValue(false, forKey: "drawsBackground")

        super.init()

        messageRouter.setController(self)

        // Register JS → Swift message handler
        userContent.add(self, name: "notch")

        // Set up panel content
        panel.contentView = webView
        panel.setFrame(geometry.collapsedFrame, display: true)

        // Load the web UI; inject geometry CSS variables on load
        webView.navigationDelegate = self
        webView.load(URLRequest(url: Config.uiURL))

        panel.orderFrontRegardless()

        setupGlobalMouseMonitor()
    }

    // MARK: - Mouse Monitoring

    private func setupGlobalMouseMonitor() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.handleMouseMove()
        }

        NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.handleMouseMove()
            return event
        }
    }

    private func handleMouseMove() {
        let mouseLocation = NSEvent.mouseLocation

        if isExpanded {
            handleExpandedMouseMove(mouseLocation)
        } else {
            handleCollapsedMouseMove(mouseLocation)
        }
    }

    private func handleExpandedMouseMove(_ mouseLocation: NSPoint) {
        // Two-zone detection:
        // Zone 1 — Notch strip (pill area)
        // Zone 2 — Content area: dashboard below the notch
        let notchZone = geometry.pillFrame
        let contentZone = NSRect(
            x: geometry.expandedFrame.minX,
            y: geometry.expandedFrame.minY,
            width: geometry.expandedFrame.width,
            height: geometry.pillFrame.minY - geometry.expandedFrame.minY
        )

        let isInPanel = notchZone.contains(mouseLocation) || contentZone.contains(mouseLocation)

        if isInPanel {
            collapseTimer?.invalidate()
            collapseTimer = nil
        } else if collapseTimer == nil {
            collapseTimer = Timer.scheduledTimer(withTimeInterval: Config.Timing.collapseDelay, repeats: false) { [weak self] _ in
                self?.collapse()
            }
        }
    }

    private func handleCollapsedMouseMove(_ mouseLocation: NSPoint) {
        // Trigger only within the notch strip itself
        let hoverZone = geometry.pillFrame.insetBy(
            dx: Config.Geometry.hoverSlackDx,
            dy: Config.Geometry.hoverSlackDy
        )

        if hoverZone.contains(mouseLocation) {
            if expandTimer == nil {
                expandTimer = Timer.scheduledTimer(withTimeInterval: Config.Timing.expandDwell, repeats: false) { [weak self] _ in
                    guard let self = self else { return }
                    self.expandTimer = nil
                    // Re-verify mouse is still in zone at fire time
                    if hoverZone.contains(NSEvent.mouseLocation) {
                        self.expand()
                    }
                }
            }
        } else {
            expandTimer?.invalidate()
            expandTimer = nil
        }
    }

    // MARK: - Expand / Collapse

    func expand() {
        guard !isExpanded else { return }
        isExpanded = true

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Config.Timing.expandDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(geometry.expandedFrame, display: true)
        }

        webView.evaluateJavaScript("window.notchSetExpanded(true)", completionHandler: nil)
    }

    func collapse() {
        guard isExpanded else { return }
        isExpanded = false
        collapseTimer?.invalidate()
        collapseTimer = nil

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Config.Timing.collapseDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(geometry.collapsedFrame, display: true)
        }

        webView.evaluateJavaScript("window.notchSetExpanded(false)", completionHandler: nil)
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any] else { return }
        messageRouter.handle(body)
    }
}

// MARK: - WKNavigationDelegate (inject geometry CSS variables)

extension NotchController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let js = """
        document.documentElement.style.setProperty('--wing-width', '\(Int(geometry.wingWidth))px');
        document.documentElement.style.setProperty('--notch-gap', '\(Int(geometry.notchGap))px');
        document.documentElement.style.setProperty('--glow-pad', '\(Int(geometry.glowPad))px');
        document.documentElement.style.setProperty('--has-notch', '\(geometry.hasNotch ? 1 : 0)');
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
}
