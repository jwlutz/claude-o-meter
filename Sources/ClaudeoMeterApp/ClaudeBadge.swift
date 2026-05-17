import SwiftUI
import AppKit
import ClaudeoMeterCore

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

/// Renders provider badges directly to an NSImage (no SwiftUI). This
/// works regardless of menu-bar focus state — SwiftUI's ImageRenderer can't
/// always capture NSViewRepresentable content, which silently broke the
/// drain effect when the app was backgrounded.
enum ProviderBadgeImage {
    static let claudeOrange  = NSColor(red: 0.93, green: 0.45, blue: 0.28, alpha: 1.0)
    static let openAIGreen = NSColor(red: 0.07, green: 0.62, blue: 0.50, alpha: 1.0)
    /// Empty-glass: low-alpha neutral gray that adapts to light/dark menu bar.
    static let drainedColor = NSColor(white: 0.55, alpha: 0.30)

    /// Source the burst from the installed Claude.app's tray asset.
    static let claudeLogo: NSImage? = {
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

    /// Draw the OpenAI knot directly instead of using Codex.app's tray mark.
    static let openAILogo: NSImage? = {
        let size = NSSize(width: 256, height: 256)
        let result = NSImage(size: size)
        result.lockFocus()
        defer { result.unlockFocus() }

        let inset: CGFloat = 8
        let drawSize = size.width - inset * 2
        let transform = NSAffineTransform()
        transform.translateX(by: inset, yBy: inset + drawSize)
        transform.scaleX(by: drawSize / 24, yBy: -drawSize / 24)

        NSGraphicsContext.saveGraphicsState()
        transform.concat()
        NSColor.black.setFill()
        openAILogoPath().fill()
        NSGraphicsContext.restoreGraphicsState()

        result.isTemplate = true
        return result
    }()

    private struct BadgeSpec {
        let logo: NSImage?
        let activeColor: NSColor
    }

    private static func spec(for provider: UsageProviderID) -> BadgeSpec {
        switch provider {
        case .claudeCode:
            return BadgeSpec(logo: claudeLogo, activeColor: claudeOrange)
        case .codex:
            return BadgeSpec(logo: openAILogo, activeColor: openAIGreen)
        }
    }

    private static func openAILogoPath() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 22.2819, y: 9.8211))
        path.curve(to: NSPoint(x: 21.7662, y: 4.9103), controlPoint1: NSPoint(x: 22.8248, y: 8.1862), controlPoint2: NSPoint(x: 22.6369, y: 6.3967))
        path.curve(to: NSPoint(x: 15.2564, y: 2.0103), controlPoint1: NSPoint(x: 20.4571, y: 2.6316), controlPoint2: NSPoint(x: 17.8260, y: 1.4595))
        path.curve(to: NSPoint(x: 9.4920, y: 0.1311), controlPoint1: NSPoint(x: 13.8083, y: 0.3995), controlPoint2: NSPoint(x: 11.6112, y: -0.3168))
        path.curve(to: NSPoint(x: 4.9807, y: 4.1818), controlPoint1: NSPoint(x: 7.3728, y: 0.5789), controlPoint2: NSPoint(x: 5.6533, y: 2.1229))
        path.curve(to: NSPoint(x: 0.9830, y: 7.0818), controlPoint1: NSPoint(x: 3.2928, y: 4.5279), controlPoint2: NSPoint(x: 1.8360, y: 5.5847))
        path.curve(to: NSPoint(x: 1.7257, y: 14.1784), controlPoint1: NSPoint(x: -0.3404, y: 9.3568), controlPoint2: NSPoint(x: -0.0401, y: 12.2267))
        path.curve(to: NSPoint(x: 2.2367, y: 19.0891), controlPoint1: NSPoint(x: 1.1808, y: 15.8125), controlPoint2: NSPoint(x: 1.3670, y: 17.6022))
        path.curve(to: NSPoint(x: 8.7513, y: 21.9892), controlPoint1: NSPoint(x: 3.5475, y: 21.3686), controlPoint2: NSPoint(x: 6.1803, y: 22.5406))
        path.curve(to: NSPoint(x: 13.2599, y: 24.0000), controlPoint1: NSPoint(x: 9.8948, y: 23.2770), controlPoint2: NSPoint(x: 11.5377, y: 24.0097))
        path.curve(to: NSPoint(x: 19.0317, y: 19.7942), controlPoint1: NSPoint(x: 15.8937, y: 24.0024), controlPoint2: NSPoint(x: 18.2271, y: 22.3021))
        path.curve(to: NSPoint(x: 23.0294, y: 16.8941), controlPoint1: NSPoint(x: 20.7194, y: 19.4475), controlPoint2: NSPoint(x: 22.1760, y: 18.3908))
        path.curve(to: NSPoint(x: 22.2819, y: 9.8212), controlPoint1: NSPoint(x: 24.3368, y: 14.6231), controlPoint2: NSPoint(x: 24.0351, y: 11.7688))
        path.close()
        path.move(to: NSPoint(x: 13.2599, y: 22.4292))
        path.curve(to: NSPoint(x: 10.3835, y: 21.3884), controlPoint1: NSPoint(x: 12.2086, y: 22.4309), controlPoint2: NSPoint(x: 11.1903, y: 22.0624))
        path.line(to: NSPoint(x: 10.5254, y: 21.3080))
        path.line(to: NSPoint(x: 15.3037, y: 18.5498))
        path.curve(to: NSPoint(x: 15.6964, y: 17.8685), controlPoint1: NSPoint(x: 15.5456, y: 18.4079), controlPoint2: NSPoint(x: 15.6949, y: 18.1490))
        path.line(to: NSPoint(x: 15.6964, y: 11.1316))
        path.line(to: NSPoint(x: 17.7164, y: 12.3002))
        path.curve(to: NSPoint(x: 17.7544, y: 12.3522), controlPoint1: NSPoint(x: 17.7367, y: 12.3105), controlPoint2: NSPoint(x: 17.7508, y: 12.3298))
        path.line(to: NSPoint(x: 17.7544, y: 17.9348))
        path.curve(to: NSPoint(x: 13.2599, y: 22.4292), controlPoint1: NSPoint(x: 17.7491, y: 20.4148), controlPoint2: NSPoint(x: 15.7399, y: 22.4240))
        path.close()
        path.move(to: NSPoint(x: 3.5992, y: 18.3038))
        path.curve(to: NSPoint(x: 3.0646, y: 15.2901), controlPoint1: NSPoint(x: 3.0720, y: 17.3934), controlPoint2: NSPoint(x: 2.8827, y: 16.3263))
        path.line(to: NSPoint(x: 3.2066, y: 15.3753))
        path.line(to: NSPoint(x: 7.9896, y: 18.1335))
        path.curve(to: NSPoint(x: 8.7702, y: 18.1335), controlPoint1: NSPoint(x: 8.2306, y: 18.2749), controlPoint2: NSPoint(x: 8.5292, y: 18.2749))
        path.line(to: NSPoint(x: 14.6130, y: 14.7650))
        path.line(to: NSPoint(x: 14.6130, y: 17.0974))
        path.curve(to: NSPoint(x: 14.5798, y: 17.1589), controlPoint1: NSPoint(x: 14.6119, y: 17.1219), controlPoint2: NSPoint(x: 14.5997, y: 17.1445))
        path.line(to: NSPoint(x: 9.7400, y: 19.9502))
        path.curve(to: NSPoint(x: 3.5992, y: 18.3038), controlPoint1: NSPoint(x: 7.5893, y: 21.1891), controlPoint2: NSPoint(x: 4.8416, y: 20.4525))
        path.close()
        path.move(to: NSPoint(x: 2.3408, y: 7.8956))
        path.curve(to: NSPoint(x: 4.7063, y: 5.9228), controlPoint1: NSPoint(x: 2.8717, y: 6.9794), controlPoint2: NSPoint(x: 3.7096, y: 6.2805))
        path.line(to: NSPoint(x: 4.7063, y: 11.6000))
        path.curve(to: NSPoint(x: 5.0942, y: 12.2765), controlPoint1: NSPoint(x: 4.7026, y: 11.8793), controlPoint2: NSPoint(x: 4.8513, y: 12.1386))
        path.line(to: NSPoint(x: 10.9086, y: 15.6308))
        path.line(to: NSPoint(x: 8.8885, y: 16.7993))
        path.curve(to: NSPoint(x: 8.8175, y: 16.7993), controlPoint1: NSPoint(x: 8.8663, y: 16.8111), controlPoint2: NSPoint(x: 8.8397, y: 16.8111))
        path.line(to: NSPoint(x: 3.9872, y: 14.0128))
        path.curve(to: NSPoint(x: 2.3408, y: 7.8720), controlPoint1: NSPoint(x: 1.8408, y: 12.7686), controlPoint2: NSPoint(x: 1.1047, y: 10.0230))
        path.close()
        path.move(to: NSPoint(x: 18.9371, y: 11.7514))
        path.line(to: NSPoint(x: 13.1038, y: 8.3640))
        path.line(to: NSPoint(x: 15.1192, y: 7.2000))
        path.curve(to: NSPoint(x: 15.1902, y: 7.2000), controlPoint1: NSPoint(x: 15.1414, y: 7.1882), controlPoint2: NSPoint(x: 15.1680, y: 7.1882))
        path.line(to: NSPoint(x: 20.0205, y: 9.9913))
        path.curve(to: NSPoint(x: 22.2531, y: 14.2580), controlPoint1: NSPoint(x: 21.5281, y: 10.8612), controlPoint2: NSPoint(x: 22.3979, y: 12.5234))
        path.curve(to: NSPoint(x: 19.3440, y: 18.0955), controlPoint1: NSPoint(x: 22.1083, y: 15.9926), controlPoint2: NSPoint(x: 20.9750, y: 17.4876))
        path.line(to: NSPoint(x: 19.3440, y: 12.4183))
        path.curve(to: NSPoint(x: 18.9370, y: 11.7513), controlPoint1: NSPoint(x: 19.3355, y: 12.1397), controlPoint2: NSPoint(x: 19.1808, y: 11.8863))
        path.close()
        path.move(to: NSPoint(x: 20.9478, y: 8.7283))
        path.line(to: NSPoint(x: 20.8058, y: 8.6431))
        path.line(to: NSPoint(x: 16.0323, y: 5.8613))
        path.curve(to: NSPoint(x: 15.2469, y: 5.8613), controlPoint1: NSPoint(x: 15.7898, y: 5.7190), controlPoint2: NSPoint(x: 15.4894, y: 5.7190))
        path.line(to: NSPoint(x: 9.4090, y: 9.2297))
        path.line(to: NSPoint(x: 9.4090, y: 6.8974))
        path.curve(to: NSPoint(x: 9.4374, y: 6.8359), controlPoint1: NSPoint(x: 9.4065, y: 6.8732), controlPoint2: NSPoint(x: 9.4174, y: 6.8496))
        path.line(to: NSPoint(x: 14.2677, y: 4.0493))
        path.curve(to: NSPoint(x: 19.0877, y: 4.2578), controlPoint1: NSPoint(x: 15.7790, y: 3.1787), controlPoint2: NSPoint(x: 17.6573, y: 3.2599))
        path.curve(to: NSPoint(x: 20.9479, y: 8.7093), controlPoint1: NSPoint(x: 20.5182, y: 5.2556), controlPoint2: NSPoint(x: 21.2431, y: 6.9903))
        path.close()
        path.move(to: NSPoint(x: 8.3065, y: 12.8630))
        path.line(to: NSPoint(x: 6.2865, y: 11.6992))
        path.curve(to: NSPoint(x: 6.2485, y: 11.6425), controlPoint1: NSPoint(x: 6.2660, y: 11.6869), controlPoint2: NSPoint(x: 6.2521, y: 11.6661))
        path.line(to: NSPoint(x: 6.2485, y: 6.0742))
        path.curve(to: NSPoint(x: 8.8397, y: 2.0054), controlPoint1: NSPoint(x: 6.2508, y: 4.3304), controlPoint2: NSPoint(x: 7.2605, y: 2.7449))
        path.curve(to: NSPoint(x: 13.6242, y: 2.6205), controlPoint1: NSPoint(x: 10.4190, y: 1.2659), controlPoint2: NSPoint(x: 12.2833, y: 1.5056))
        path.line(to: NSPoint(x: 13.4822, y: 2.7010))
        path.line(to: NSPoint(x: 8.7040, y: 5.4590))
        path.curve(to: NSPoint(x: 8.3113, y: 6.1403), controlPoint1: NSPoint(x: 8.4621, y: 5.6009), controlPoint2: NSPoint(x: 8.3128, y: 5.8598))
        path.close()
        path.move(to: NSPoint(x: 9.4041, y: 10.4976))
        path.line(to: NSPoint(x: 12.0061, y: 8.9978))
        path.line(to: NSPoint(x: 14.6130, y: 10.4976))
        path.line(to: NSPoint(x: 14.6130, y: 13.4970))
        path.line(to: NSPoint(x: 12.0156, y: 14.9967))
        path.line(to: NSPoint(x: 9.4089, y: 13.4970))
        path.close()
        return path
    }

    /// Provider logo with a pie-chart "empty" effect.
    /// The gray ghost is drawn first as the baseline; the bright orange is
    /// then clipped to the *remaining* wedge and stacked on top, so the used
    /// wedge naturally falls through to the ghost (no muddy blend).
    ///
    /// Edge cases: at fraction=0 a wedge from 90° to 90° is degenerate
    /// (zero arc) and clips to nothing — the icon would appear empty/gone
    /// right when the user just got their 5h reset. Special-case both ends.
    static func render(provider: UsageProviderID, fraction: Double, pointSize: CGFloat = 22) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        let result = NSImage(size: size)
        result.lockFocus()
        defer { result.unlockFocus() }

        let spec = spec(for: provider)
        guard let logo = spec.logo else { return result }
        let bounds = NSRect(origin: .zero, size: size)
        let used = max(0, min(1, fraction))

        if used <= 0.001 {
            // Fresh — full bright orange, no clip.
            logo.tinted(spec.activeColor).draw(in: bounds)
            return result
        }
        if used >= 0.999 {
            // Fully drained — only the gray ghost.
            logo.tinted(drainedColor).draw(in: bounds)
            return result
        }

        // Partial: gray baseline + bright orange wedge for the remaining slice.
        logo.tinted(drainedColor).draw(in: bounds)
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
        logo.tinted(spec.activeColor).draw(in: bounds)
        NSGraphicsContext.restoreGraphicsState()

        return result
    }
}

enum MenuBarPillImage {
    static func render(snapshot: UsageSnapshot,
                       providers: [UsageProviderID],
                       showTimer: Bool,
                       pointHeight: CGFloat = 28,
                       now: Date = Date()) -> NSImage {
        let pillWidth: CGFloat = showTimer ? 104 : 38
        let gap: CGFloat = 7
        let width = CGFloat(providers.count) * pillWidth + CGFloat(max(0, providers.count - 1)) * gap
        let size = NSSize(width: width, height: pointHeight)
        let result = NSImage(size: size)
        result.lockFocus()
        defer { result.unlockFocus() }

        for (index, provider) in providers.enumerated() {
            let x = CGFloat(index) * (pillWidth + gap)
            drawPill(
                provider: provider,
                providerSnapshot: snapshot.provider(provider),
                showTimer: showTimer,
                frame: NSRect(x: x, y: 1, width: pillWidth, height: pointHeight - 2),
                now: now
            )
        }

        return result
    }

    private static func drawPill(provider: UsageProviderID,
                                 providerSnapshot: ProviderUsageSnapshot?,
                                 showTimer: Bool,
                                 frame: NSRect,
                                 now: Date) {
        let radius = frame.height / 2
        let background = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
        NSColor(white: 1.0, alpha: 0.86).setFill()
        background.fill()
        NSColor(white: 0.0, alpha: 0.16).setStroke()
        background.lineWidth = 1
        background.stroke()

        let window = providerSnapshot?.mode.subscriptionStats?.primaryWindow
        let fraction = min(1.0, max(0, (window?.usedPercent ?? 100) / 100.0))
        let iconSize: CGFloat = 22
        let icon = ProviderBadgeImage.render(provider: provider, fraction: fraction, pointSize: iconSize)
        icon.draw(in: NSRect(x: frame.minX + 7, y: frame.midY - iconSize / 2, width: iconSize, height: iconSize))

        guard showTimer else { return }
        let timer = window?.resetText(relativeTo: now) ?? "--"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.black,
        ]
        let textSize = timer.size(withAttributes: attributes)
        let textRect = NSRect(
            x: frame.minX + 36,
            y: frame.midY - textSize.height / 2 - 0.5,
            width: frame.width - 43,
            height: textSize.height
        )
        timer.draw(in: textRect, withAttributes: attributes)
    }
}

private extension UsageMode {
    var subscriptionStats: ProviderUsageStats? {
        guard case .subscription(let stats) = self else { return nil }
        return stats
    }
}

/// SwiftUI wrapper for popover use (slightly larger pies inside rows).
struct ProviderBadge: View {
    let provider: UsageProviderID
    let fraction: Double

    var body: some View {
        Image(nsImage: ProviderBadgeImage.render(provider: provider, fraction: fraction, pointSize: 64))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .animation(.easeInOut(duration: 0.4), value: fraction)
    }
}
