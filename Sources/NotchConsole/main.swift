import AppKit
import WebKit

// MARK: - OverlayPanel

/// Non-activating, borderless, transparent panel for the notch overlay.
final class OverlayPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovable = false
        hidesOnDeactivate = false
        worksWhenModal = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - NotchGeometry

struct NotchGeometry {
    let hasNotch: Bool
    let collapsedFrame: NSRect
    let expandedFrame: NSRect

    static func detect() -> NotchGeometry {
        guard let screen = NSScreen.main else {
            return NotchGeometry(
                hasNotch: false,
                collapsedFrame: NSRect(x: 100, y: 100, width: 240, height: 32),
                expandedFrame: NSRect(x: 100, y: 100, width: 420, height: 220)
            )
        }

        let hasNotch: Bool
        let pillWidth: CGFloat = 240
        let pillHeight: CGFloat = 32
        let expandedWidth: CGFloat = 420
        let expandedHeight: CGFloat = 220

        if let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea {
            hasNotch = true

            // Notch gap: between leftArea.maxX and rightArea.minX
            let notchCenter = (leftArea.maxX + rightArea.minX) / 2

            // Collapsed: pill centered above notch, in menu bar area
            let collapsedX = notchCenter - pillWidth / 2
            let collapsedY = screen.frame.maxY - pillHeight

            // Expanded: drops down below menu bar
            let expandedX = notchCenter - expandedWidth / 2
            let expandedY = screen.frame.maxY - expandedHeight

            return NotchGeometry(
                hasNotch: hasNotch,
                collapsedFrame: NSRect(x: collapsedX, y: collapsedY, width: pillWidth, height: pillHeight),
                expandedFrame: NSRect(x: expandedX, y: expandedY, width: expandedWidth, height: expandedHeight)
            )
        } else {
            hasNotch = false

            // Fallback: centered floating bar at top of screen
            let centerX = screen.frame.midX - pillWidth / 2
            let topY = screen.frame.maxY - pillHeight - 4

            let expandedX = screen.frame.midX - expandedWidth / 2
            let expandedY = screen.frame.maxY - expandedHeight - 4

            return NotchGeometry(
                hasNotch: hasNotch,
                collapsedFrame: NSRect(x: centerX, y: topY, width: pillWidth, height: pillHeight),
                expandedFrame: NSRect(x: expandedX, y: expandedY, width: expandedWidth, height: expandedHeight)
            )
        }
    }
}

// MARK: - NotchController

/// Manages the overlay panel, WebView, and hover interactions.
final class NotchController: NSObject, WKScriptMessageHandler {
    let panel: OverlayPanel
    let webView: WKWebView
    let geometry: NotchGeometry
    private var isExpanded = false
    private var mouseMonitor: Any?
    private var collapseTimer: Timer?

    override init() {
        self.geometry = NotchGeometry.detect()
        self.panel = OverlayPanel()

        // Configure WKWebView
        let config = WKWebViewConfiguration()
        let userContent = WKUserContentController()
        config.userContentController = userContent
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        self.webView = WKWebView(frame: .zero, configuration: config)
        self.webView.setValue(false, forKey: "drawsBackground")

        super.init()

        // Register JS → Swift message handler
        userContent.add(self, name: "notch")

        // Set up panel content
        panel.contentView = webView
        panel.setFrame(geometry.collapsedFrame, display: true)

        // Load the web UI
        let url = URL(string: "http://127.0.0.1:23456/ui/index.html")!
        webView.load(URLRequest(url: url))

        panel.orderFrontRegardless()

        // Use global mouse monitoring (works for non-activating panels)
        setupGlobalMouseMonitor()
    }

    private func setupGlobalMouseMonitor() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.handleMouseMove()
        }

        // Also monitor local events (when mouse is over our own panel)
        NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.handleMouseMove()
            return event
        }
    }

    private func handleMouseMove() {
        let mouseLocation = NSEvent.mouseLocation
        let hitFrame = isExpanded ? geometry.expandedFrame : geometry.collapsedFrame

        // Add a generous hover zone around the panel
        let hoverZone = hitFrame.insetBy(dx: -20, dy: -10)

        if hoverZone.contains(mouseLocation) {
            collapseTimer?.invalidate()
            collapseTimer = nil
            expand()
        } else if isExpanded {
            // Delay collapse slightly to prevent flickering
            if collapseTimer == nil {
                collapseTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                    self?.collapse()
                }
            }
        }
    }

    // MARK: - Expand / Collapse

    func expand() {
        guard !isExpanded else { return }
        isExpanded = true

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
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
            context.duration = 0.2
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
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }

        switch action {
        case "expand":
            expand()
        case "collapse":
            collapse()
        default:
            break
        }
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller = NotchController()
    }
}

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
