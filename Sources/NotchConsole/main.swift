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

        if let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea {
            // Use the exact notch gap as the collapsed pill width
            let notchGap    = rightArea.minX - leftArea.maxX
            let notchCenter = (leftArea.maxX + rightArea.minX) / 2
            let pillHeight: CGFloat = 30

            // Collapsed: pixel-perfect match to the physical notch
            let collapsedX = leftArea.maxX
            let collapsedY = screen.frame.maxY - pillHeight

            // Expanded: grows symmetrically outward and downward from notch
            let expandedWidth: CGFloat  = notchGap + 200
            let expandedHeight: CGFloat = 260
            let expandedX = notchCenter - expandedWidth / 2
            let expandedY = screen.frame.maxY - expandedHeight

            return NotchGeometry(
                hasNotch: true,
                collapsedFrame: NSRect(x: collapsedX, y: collapsedY, width: notchGap, height: pillHeight),
                expandedFrame:  NSRect(x: expandedX,  y: expandedY,  width: expandedWidth, height: expandedHeight)
            )
        } else {
            // Fallback: floating pill for non-notch displays
            let pillWidth: CGFloat  = 220
            let pillHeight: CGFloat = 32
            let expandedWidth: CGFloat  = 380
            let expandedHeight: CGFloat = 240

            let centerX   = screen.frame.midX - pillWidth / 2
            let topY      = screen.frame.maxY - pillHeight - 6
            let expandedX = screen.frame.midX - expandedWidth / 2
            let expandedY = screen.frame.maxY - expandedHeight - 6

            return NotchGeometry(
                hasNotch: false,
                collapsedFrame: NSRect(x: centerX,   y: topY,      width: pillWidth,    height: pillHeight),
                expandedFrame:  NSRect(x: expandedX, y: expandedY, width: expandedWidth, height: expandedHeight)
            )
        }
    }
}

// MARK: - NotchController

/// Manages the overlay panel, WebView, hover interactions, and sound.
final class NotchController: NSObject, WKScriptMessageHandler {
    let panel: OverlayPanel
    let webView: WKWebView
    let geometry: NotchGeometry
    private var isExpanded = false
    private var isMuted = false
    private var mouseMonitor: Any?
    private var collapseTimer: Timer?
    private var expandTimer: Timer?
    private var lastSoundTime: [String: Date] = [:]  // debounce per sound category

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

        if isExpanded {
            // Two-zone detection (like VibeIsland):
            // Zone 1 — Notch strip: narrow area at screen top (pill width only)
            //          Keeps panel open when mouse is in the notch area
            // Zone 2 — Content area: the visible dashboard below the notch
            //          Full expanded width, from notch bottom to panel bottom
            let notchZone = geometry.collapsedFrame
            let contentZone = NSRect(
                x: geometry.expandedFrame.minX,
                y: geometry.expandedFrame.minY,
                width: geometry.expandedFrame.width,
                height: geometry.collapsedFrame.minY - geometry.expandedFrame.minY
            )

            let isInPanel = notchZone.contains(mouseLocation) || contentZone.contains(mouseLocation)

            if isInPanel {
                collapseTimer?.invalidate()
                collapseTimer = nil
            } else if collapseTimer == nil {
                collapseTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
                    self?.collapse()
                }
            }
        } else {
            // Collapsed: trigger only within the notch strip itself (no downward expansion).
            // Horizontal slack ±20px for easier targeting; dy = 0 prevents accidental
            // triggers when scrolling near the menu bar.
            let hoverZone = geometry.collapsedFrame.insetBy(dx: -20, dy: -4)
            if hoverZone.contains(mouseLocation) {
                // Schedule expand timer on first entry; mouse can stop moving and it still fires.
                if expandTimer == nil {
                    expandTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
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

    // MARK: - Sound

    private static let soundMap: [String: String] = [
        "complete": "/System/Library/Sounds/Glass.aiff",
        "error": "/System/Library/Sounds/Sosumi.aiff",
        "attention": "/System/Library/Sounds/Ping.aiff",
    ]

    private func playSound(_ name: String) {
        guard !isMuted else { return }

        // Debounce: same sound category at most once per 3 seconds
        let now = Date()
        if let last = lastSoundTime[name], now.timeIntervalSince(last) < 3.0 {
            return
        }
        lastSoundTime[name] = now

        guard let path = Self.soundMap[name],
              let sound = NSSound(contentsOfFile: path, byReference: true) else { return }
        sound.volume = 0.4
        sound.play()
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else {
            // Legacy: support old action-based messages
            if let body = message.body as? [String: Any],
               let action = body["action"] as? String {
                switch action {
                case "expand": expand()
                case "collapse": collapse()
                default: break
                }
            }
            return
        }

        switch type {
        case "playSound":
            if let value = body["value"] as? String {
                playSound(value)
            }
        case "toggleMute":
            isMuted = !isMuted
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
