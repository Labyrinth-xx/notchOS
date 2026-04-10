import AppKit
import WebKit

/// Manages the overlay panel, WebView, hover interactions, and delegates sound/messages.
final class NotchController: NSObject, WKScriptMessageHandler {
    let panel: OverlayPanel
    let webView: WKWebView
    let geometry: NotchGeometry
    let soundManager: SoundManager
    let messageRouter: MessageRouter
    let settingsWindow: SettingsWindowController
    var nowPlayingMonitor: NowPlayingMonitor?

    private var isExpanded = false
    private(set) var isSplit = false
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var collapseTimer: Timer?
    private var expandTimer: Timer?

    override init() {
        self.geometry = NotchGeometry.detect()
        self.panel = OverlayPanel()
        self.soundManager = SoundManager()
        self.messageRouter = MessageRouter(soundManager: soundManager)
        self.settingsWindow = SettingsWindowController()

        // Configure WKWebView
        let config = WKWebViewConfiguration()
        let userContent = WKUserContentController()
        config.userContentController = userContent
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        self.webView = WKWebView(frame: .zero, configuration: config)
        self.webView.setValue(false, forKey: "drawsBackground")

        super.init()

        messageRouter.setController(self)
        settingsWindow.notchController = self

        // Register JS → Swift message handler
        userContent.add(self, name: "notch")

        // Set up panel content
        panel.contentView = webView
        panel.setFrame(geometry.collapsedFrame, display: true)

        // Load the web UI; inject geometry CSS variables on load
        webView.navigationDelegate = self
        webView.load(URLRequest(url: Config.uiURL))

        panel.orderFrontRegardless()

        // Start music monitoring
        nowPlayingMonitor = NowPlayingMonitor(webView: webView)

        // Request notification permission for timer
        messageRouter.requestNotificationPermission()

        setupGlobalMouseMonitor()
    }

    // MARK: - Mouse Monitoring

    private func setupGlobalMouseMonitor() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.handleMouseMove()
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
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
        let isInPanel = geometry.expandedFrame.contains(mouseLocation)

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
        let pillZone = geometry.pillFrame.insetBy(
            dx: Config.Geometry.hoverSlackDx,
            dy: Config.Geometry.hoverSlackDy
        )

        // In split mode, also check the left bubble area
        let leftBubbleZone = geometry.leftBubbleFrame.insetBy(
            dx: Config.Geometry.hoverSlackDx,
            dy: Config.Geometry.hoverSlackDy
        )
        let isInHoverZone = pillZone.contains(mouseLocation)
            || (isSplit && leftBubbleZone.contains(mouseLocation))

        if isInHoverZone {
            if expandTimer == nil {
                expandTimer = Timer.scheduledTimer(withTimeInterval: Config.Timing.expandDwell, repeats: false) { [weak self] _ in
                    guard let self = self else { return }
                    self.expandTimer = nil
                    let current = NSEvent.mouseLocation
                    let stillIn = pillZone.contains(current)
                        || (self.isSplit && leftBubbleZone.contains(current))
                    if stillIn {
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
        panel.ignoresMouseEvents = false

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
        panel.ignoresMouseEvents = true

        let targetFrame = isSplit ? geometry.splitCollapsedFrame : geometry.collapsedFrame
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Config.Timing.collapseDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(targetFrame, display: true)
        }

        webView.evaluateJavaScript("window.notchSetExpanded(false)", completionHandler: nil)
    }

    // MARK: - Split Mode

    func setSplit(_ split: Bool) {
        guard split != isSplit, !isExpanded else { return }
        isSplit = split

        let targetFrame = split ? geometry.splitCollapsedFrame : geometry.collapsedFrame
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Config.Timing.expandDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(targetFrame, display: true)
        }

        webView.evaluateJavaScript("window.notchSetSplit(\(split))", completionHandler: nil)
    }

    // MARK: - Settings

    func reloadSettingsInDashboard() {
        webView.evaluateJavaScript("window.reloadSettings && window.reloadSettings()", completionHandler: nil)
    }

    func applySetting(key: String, rawValue: Any?) {
        switch key {
        case "hideInFullscreen":
            let hide = (rawValue as? Bool) ?? false
            if hide {
                panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
            } else {
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            }
        default:
            break
        }
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
        // Calculate left bubble position relative to the split panel frame
        let leftBubble = geometry.leftBubbleFrame
        let splitFrame = geometry.splitCollapsedFrame

        // In split mode, the panel origin changes — compute relative to splitCollapsedFrame
        let bubbleRelX = leftBubble.origin.x - splitFrame.origin.x
        let bubbleRelY = splitFrame.height - (leftBubble.origin.y - splitFrame.origin.y) - leftBubble.height

        let js = """
        document.documentElement.style.setProperty('--wing-width', '\(Int(geometry.wingWidth))px');
        document.documentElement.style.setProperty('--notch-gap', '\(Int(geometry.notchGap))px');
        document.documentElement.style.setProperty('--glow-pad', '\(Int(geometry.glowPad))px');
        document.documentElement.style.setProperty('--has-notch', '\(geometry.hasNotch ? 1 : 0)');
        document.documentElement.style.setProperty('--expanded-height', '\(Int(geometry.expandedFrame.height))px');
        document.documentElement.style.setProperty('--left-bubble-x', '\(Int(bubbleRelX))px');
        document.documentElement.style.setProperty('--left-bubble-y', '\(Int(bubbleRelY))px');
        document.documentElement.style.setProperty('--left-bubble-w', '\(Int(leftBubble.width))px');
        document.documentElement.style.setProperty('--left-bubble-h', '\(Int(leftBubble.height))px');
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
}
