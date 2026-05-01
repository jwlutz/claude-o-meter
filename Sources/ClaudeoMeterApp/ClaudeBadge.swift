import SwiftUI
import AppKit

private extension NSImage {
    /// Tint a template-style NSImage. Uses `.sourceIn` so the original alpha
    /// shape is kept but the color is fully replaced (vs `.sourceAtop` which
    /// blends with the original black, producing muddy output).
    func tinted(_ color: NSColor) -> NSImage {
        let result = NSImage(size: self.size)
        result.lockFocus()
        defer { result.unlockFocus() }
        let rect = NSRect(origin: .zero, size: self.size)
        self.draw(in: rect)
        color.set()
        rect.fill(using: .sourceIn)
        return result
    }
}

/// Renders the Claude burst badge directly to an NSImage (no SwiftUI). This
/// works regardless of menu-bar focus state — SwiftUI's ImageRenderer can't
/// always capture NSViewRepresentable content, which silently broke the
/// drain effect when the app was backgrounded.
enum ClaudeBadgeImage {
    static let claudeOrange  = NSColor(red: 0.93, green: 0.45, blue: 0.28, alpha: 1.0)
    /// Empty-glass: low-alpha neutral gray that adapts to light/dark menu bar.
    static let drainedOrange = NSColor(white: 0.55, alpha: 0.30)

    /// Source the burst from the installed Claude.app's tray asset.
    static let logo: NSImage? = {
        let candidates = [
            "/Applications/Claude.app/Contents/Resources/TrayIconTemplate@3x.png",
            "/Applications/Claude.app/Contents/Resources/TrayIconTemplate@2x.png",
            "/Applications/Claude.app/Contents/Resources/TrayIconTemplate.png",
        ]
        for path in candidates {
            if let img = NSImage(contentsOfFile: path) {
                img.isTemplate = true
                return img
            }
        }
        return nil
    }()

    /// Claude logo with a pie-chart "empty" effect.
    /// The gray ghost is drawn first as the baseline; the bright orange is
    /// then clipped to the *remaining* wedge and stacked on top, so the used
    /// wedge naturally falls through to the ghost (no muddy blend).
    ///
    /// Edge cases: at fraction=0 a wedge from 90° to 90° is degenerate
    /// (zero arc) and clips to nothing — the icon would appear empty/gone
    /// right when the user just got their 5h reset. Special-case both ends.
    static func render(fraction: Double, pointSize: CGFloat = 22) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        let result = NSImage(size: size)
        result.lockFocus()
        defer { result.unlockFocus() }

        guard let logo else { return result }
        let bounds = NSRect(origin: .zero, size: size)
        let used = max(0, min(1, fraction))

        if used <= 0.001 {
            // Fresh — full bright orange, no clip.
            logo.tinted(claudeOrange).draw(in: bounds)
            return result
        }
        if used >= 0.999 {
            // Fully drained — only the gray ghost.
            logo.tinted(drainedOrange).draw(in: bounds)
            return result
        }

        // Partial: gray baseline + bright orange wedge for the remaining slice.
        logo.tinted(drainedOrange).draw(in: bounds)
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius = hypot(bounds.width, bounds.height)
        let usedEnd = 90 - used * 360

        let slice = NSBezierPath()
        slice.move(to: center)
        slice.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: usedEnd,
            endAngle: 90,
            clockwise: true
        )
        slice.close()

        NSGraphicsContext.saveGraphicsState()
        slice.addClip()
        logo.tinted(claudeOrange).draw(in: bounds)
        NSGraphicsContext.restoreGraphicsState()

        return result
    }
}

/// SwiftUI wrapper for popover use (slightly larger pies inside rows).
struct ClaudeBadge: View {
    let fraction: Double

    var body: some View {
        Image(nsImage: ClaudeBadgeImage.render(fraction: fraction, pointSize: 64))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .animation(.easeInOut(duration: 0.4), value: fraction)
    }
}
