import SwiftUI
import AppKit

private extension NSImage {
    /// Tint a template-style NSImage. Uses `.sourceIn` which keeps the
    /// destination's alpha shape but fully replaces the color (vs `.sourceAtop`
    /// which blends with the original black, producing dark muddy output).
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
/// works reliably regardless of menu-bar focus state — SwiftUI's ImageRenderer
/// can't always capture NSViewRepresentable content, which broke the prior
/// approach when the app was backgrounded.
enum ClaudeBadgeImage {
    static let claudeOrange  = NSColor(red: 0.93, green: 0.45, blue: 0.28, alpha: 1.0)
    /// Empty-glass: low-alpha neutral gray that adapts to light/dark menu bar.
    static let drainedOrange = NSColor(white: 0.55, alpha: 0.30)

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
    /// Layer order matters: the gray ghost is drawn first as the baseline so
    /// the used wedge naturally shows the ghost (no muddy blend). The bright
    /// orange is then clipped to the *remaining* wedge and stacked on top.
    static func render(fraction: Double, pointSize: CGFloat = 20) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        let result = NSImage(size: size)
        result.lockFocus()
        defer { result.unlockFocus() }

        guard let logo else { return result }
        let bounds = NSRect(origin: .zero, size: size)

        // 1. Gray ghost baseline (alpha < 1 = subtle outline of full burst).
        logo.tinted(drainedOrange).draw(in: bounds)

        // 2. Bright orange in the remaining wedge.
        let used = max(0, min(1, fraction))
        let remaining = 1 - used
        if remaining > 0.001 {
            let center = NSPoint(x: bounds.midX, y: bounds.midY)
            let radius = hypot(bounds.width, bounds.height)
            let usedEnd = 90 - used * 360  // angle where the used slice ends

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
        }

        return result
    }
}

/// SwiftUI version retained for the popover preview (smaller usages where
/// ImageRenderer isn't involved). Wraps the NSImage compositor.
struct ClaudeBadge: View {
    let fraction: Double

    var body: some View {
        Image(nsImage: ClaudeBadgeImage.render(fraction: fraction, pointSize: 44))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .animation(.easeInOut(duration: 0.4), value: fraction)
    }
}

/// Larger filled-pie variant for the popover rows.
struct FilledPie: View {
    let fraction: Double
    var fillColor: Color {
        switch fraction {
        case ..<0.6: return .green
        case ..<0.85: return .yellow
        default: return .red
        }
    }
    var body: some View {
        ZStack {
            Circle().fill(Color.secondary.opacity(0.2))
            PieSlice(fraction: max(0.001, min(1.0, fraction))).fill(fillColor)
            Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 0.5)
        }
    }
}

struct PieSlice: Shape {
    var fraction: Double
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        p.move(to: center)
        p.addArc(center: center,
                 radius: radius,
                 startAngle: .degrees(-90),
                 endAngle: .degrees(-90 + fraction * 360),
                 clockwise: false)
        p.closeSubpath()
        return p
    }
}
