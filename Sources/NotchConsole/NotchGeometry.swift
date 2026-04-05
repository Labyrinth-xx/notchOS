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

        return NotchGeometry(
            hasNotch: true,
            wingWidth: wingWidth,
            notchGap: notchGap,
            glowPad: glowPad,
            pillFrame: pillRect,
            collapsedFrame: NSRect(x: collapsedX, y: collapsedY, width: collapsedWidth, height: collapsedHeight),
            expandedFrame: NSRect(x: expandedX, y: expandedY, width: expandedWidth, height: expandedHeight)
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

        return NotchGeometry(
            hasNotch: false,
            wingWidth: wingWidth,
            notchGap: centerWidth,
            glowPad: glowPad,
            pillFrame: pillRect,
            collapsedFrame: NSRect(
                x: pillX - glowPad,
                y: pillY - glowPad,
                width: pillWidth + glowPad * 2,
                height: pillHeight + glowPad
            ),
            expandedFrame: NSRect(x: expandedX, y: expandedY, width: expandedWidth, height: expandedHeight)
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

        return NotchGeometry(
            hasNotch: false,
            wingWidth: wingWidth,
            notchGap: centerWidth,
            glowPad: glowPad,
            pillFrame: pillRect,
            collapsedFrame: NSRect(x: 100, y: 100, width: pillW + glowPad * 2, height: pillHeight + glowPad),
            expandedFrame: NSRect(x: 100, y: 100, width: 420, height: 220)
        )
    }
}
