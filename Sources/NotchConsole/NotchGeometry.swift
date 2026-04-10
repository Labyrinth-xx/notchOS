import AppKit

/// Detects physical notch position and calculates UI frame geometries.
struct NotchGeometry {
    let hasNotch: Bool
    let wingWidth: CGFloat
    let notchGap: CGFloat
    let glowPad: CGFloat
    let pillFrame: NSRect
    let collapsedFrame: NSRect
    let expandedFrame: NSRect
    /// Secondary bubble in left wing area (for split-pill Dynamic Island mode)
    let leftBubbleFrame: NSRect
    /// Panel frame when in split mode (covers both bubbles + glow)
    let splitCollapsedFrame: NSRect

    static func detect() -> NotchGeometry {
        let wingWidth = Config.Geometry.wingWidth
        let glowPad = Config.Geometry.glowPad
        let pillHeight = Config.Geometry.pillHeight

        guard let screen = NSScreen.main else {
            return fallbackGeometry(wingWidth: wingWidth, glowPad: glowPad, pillHeight: pillHeight)
        }

        if let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea {
            return notchGeometry(
                screen: screen,
                leftArea: leftArea,
                rightArea: rightArea,
                wingWidth: wingWidth,
                glowPad: glowPad,
                pillHeight: pillHeight
            )
        } else {
            return nonNotchGeometry(
                screen: screen,
                wingWidth: wingWidth,
                glowPad: glowPad,
                pillHeight: pillHeight
            )
        }
    }

    // MARK: - Private Geometry Builders

    private static func notchGeometry(
        screen: NSScreen,
        leftArea: NSRect,
        rightArea: NSRect,
        wingWidth: CGFloat,
        glowPad: CGFloat,
        pillHeight: CGFloat
    ) -> NotchGeometry {
        let notchGap = rightArea.minX - leftArea.maxX
        let notchCenter = (leftArea.maxX + rightArea.minX) / 2

        // Pill: visual rectangle (notch gap + wings)
        let pillWidth = notchGap + wingWidth * 2
        let pillX = leftArea.maxX - wingWidth
        let pillY = screen.frame.maxY - pillHeight
        let pillRect = NSRect(x: pillX, y: pillY, width: pillWidth, height: pillHeight)

        // Collapsed panel: pill + glow padding on left, right, bottom
        let collapsedX = pillX - glowPad
        let collapsedY = pillY - glowPad
        let collapsedWidth = pillWidth + glowPad * 2
        let collapsedHeight = pillHeight + glowPad

        // Expanded: grows symmetrically outward and downward from notch
        let expandedWidth = notchGap + Config.Geometry.expandedExtraWidth
        let expandedHeight = Config.Geometry.expandedHeight
        let expandedX = notchCenter - expandedWidth / 2
        let expandedY = screen.frame.maxY - expandedHeight

        // Left bubble: small pill in the left wing area, right-aligned to notch edge
        let bubbleW = Config.Geometry.secondaryBubbleWidth
        let bubbleH = Config.Geometry.secondaryBubbleHeight
        let leftBubbleX = leftArea.maxX - bubbleW
        let leftBubbleY = screen.frame.maxY - bubbleH
        let leftBubble = NSRect(x: leftBubbleX, y: leftBubbleY, width: bubbleW, height: bubbleH)

        // Split collapsed: panel must cover both left bubble and main pill (+ glow padding)
        let splitLeft = leftBubbleX - glowPad
        let splitRight = pillX + pillWidth + glowPad
        let splitBottom = min(leftBubbleY, pillY) - glowPad
        let splitTop = screen.frame.maxY
        let splitCollapsed = NSRect(
            x: splitLeft,
            y: splitBottom,
            width: splitRight - splitLeft,
            height: splitTop - splitBottom
        )

        return NotchGeometry(
            hasNotch: true,
            wingWidth: wingWidth,
            notchGap: notchGap,
            glowPad: glowPad,
            pillFrame: pillRect,
            collapsedFrame: NSRect(x: collapsedX, y: collapsedY, width: collapsedWidth, height: collapsedHeight),
            expandedFrame: NSRect(x: expandedX, y: expandedY, width: expandedWidth, height: expandedHeight),
            leftBubbleFrame: leftBubble,
            splitCollapsedFrame: splitCollapsed
        )
    }

    private static func nonNotchGeometry(
        screen: NSScreen,
        wingWidth: CGFloat,
        glowPad: CGFloat,
        pillHeight: CGFloat
    ) -> NotchGeometry {
        let centerWidth = Config.Geometry.fallbackCenterWidth
        let pillWidth = centerWidth + wingWidth * 2
        let topOffset = Config.Geometry.fallbackTopOffset

        let pillX = screen.frame.midX - pillWidth / 2
        let pillY = screen.frame.maxY - pillHeight - topOffset
        let pillRect = NSRect(x: pillX, y: pillY, width: pillWidth, height: pillHeight)

        let expandedWidth = Config.Geometry.fallbackExpandedWidth
        let expandedHeight = Config.Geometry.fallbackExpandedHeight
        let expandedX = screen.frame.midX - expandedWidth / 2
        let expandedY = screen.frame.maxY - expandedHeight - topOffset

        let collapsed = NSRect(
            x: pillX - glowPad,
            y: pillY - glowPad,
            width: pillWidth + glowPad * 2,
            height: pillHeight + glowPad
        )

        // Non-notch: left bubble placed to the left of the pill
        let bubbleW = Config.Geometry.secondaryBubbleWidth
        let bubbleH = Config.Geometry.secondaryBubbleHeight
        let leftBubbleX = pillX - bubbleW - 8
        let leftBubbleY = screen.frame.maxY - bubbleH - topOffset
        let leftBubble = NSRect(x: leftBubbleX, y: leftBubbleY, width: bubbleW, height: bubbleH)
        let splitCollapsed = NSRect(
            x: leftBubbleX - glowPad,
            y: min(leftBubbleY, pillY) - glowPad,
            width: (pillX + pillWidth + glowPad) - (leftBubbleX - glowPad),
            height: pillHeight + glowPad
        )

        return NotchGeometry(
            hasNotch: false,
            wingWidth: wingWidth,
            notchGap: centerWidth,
            glowPad: glowPad,
            pillFrame: pillRect,
            collapsedFrame: collapsed,
            expandedFrame: NSRect(x: expandedX, y: expandedY, width: expandedWidth, height: expandedHeight),
            leftBubbleFrame: leftBubble,
            splitCollapsedFrame: splitCollapsed
        )
    }

    private static func fallbackGeometry(
        wingWidth: CGFloat,
        glowPad: CGFloat,
        pillHeight: CGFloat
    ) -> NotchGeometry {
        let centerWidth = Config.Geometry.fallbackCenterWidth
        let pillW = centerWidth + wingWidth * 2
        let pillRect = NSRect(x: 100 + glowPad, y: 100 + glowPad, width: pillW, height: pillHeight)

        let leftBubble = NSRect(x: 100 + glowPad - 44, y: 100 + glowPad, width: 36, height: 30)
        return NotchGeometry(
            hasNotch: false,
            wingWidth: wingWidth,
            notchGap: centerWidth,
            glowPad: glowPad,
            pillFrame: pillRect,
            collapsedFrame: NSRect(x: 100, y: 100, width: pillW + glowPad * 2, height: pillHeight + glowPad),
            expandedFrame: NSRect(x: 100, y: 100, width: 420, height: 220),
            leftBubbleFrame: leftBubble,
            splitCollapsedFrame: NSRect(x: 56, y: 100, width: pillW + glowPad * 2 + 44, height: pillHeight + glowPad)
        )
    }
}
