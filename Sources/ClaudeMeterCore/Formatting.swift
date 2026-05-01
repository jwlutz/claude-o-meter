import Foundation

public enum Formatting {
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

    public static func compactTokens(_ n: Int) -> String {
        if n >= 1_000_000_000 { return String(format: "%.1fB", Double(n) / 1_000_000_000) }
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fk", Double(n) / 1_000) }
        return "\(n)"
    }

    public static func usd(_ amount: Double) -> String {
        if amount >= 100 { return String(format: "$%.0f", amount) }
        if amount >= 10 { return String(format: "$%.1f", amount) }
        return String(format: "$%.2f", amount)
    }

    public static func usdCompact(_ amount: Double) -> String {
        // Menu-bar friendly: drops the dollar sign and trailing zeros for small values
        if amount >= 100 { return String(format: "$%.0f", amount) }
        if amount >= 10 { return String(format: "$%.1f", amount) }
        return String(format: "$%.2f", amount)
    }
}
