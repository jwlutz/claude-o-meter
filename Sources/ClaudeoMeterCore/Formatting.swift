import Foundation

public enum Formatting {
    /// "4h12m" / "23m" / "2d3h" — countdown rendered relative to now.
    public static func compactDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        let h = s / 3600
        let m = (s % 3600) / 60
        if h >= 24 {
            let d = h / 24
            let rh = h % 24
            return rh == 0 ? "\(d)d" : "\(d)d\(rh)h"
        }
        if h > 0 { return "\(h)h\(m)m" }
        return "\(m)m"
    }
}

/// Pretty-print Anthropic's plan tier strings ("default_claude_max_20x" etc.)
/// for the popover badge.
public enum PlanLabel {
    public static func display(_ raw: String) -> String {
        switch true {
        case raw.contains("max_20x"): return "Max 20x"
        case raw.contains("max_5x"):  return "Max 5x"
        case raw.contains("pro"):     return "Pro"
        case raw == "subscription":   return "Subscription"
        default:                      return raw
        }
    }
}
