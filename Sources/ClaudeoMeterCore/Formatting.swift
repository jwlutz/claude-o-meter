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

/// Pretty-print plan tier strings without binding the UI to a single provider.
public enum PlanLabel {
    public static func display(_ raw: String) -> String {
        let normalized = raw
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .lowercased()

        let tokens = normalized
            .split(separator: "_")
            .map(String.init)
            .filter { token in
                !["default", "claude", "codex", "chatgpt", "openai", "subscription"].contains(token)
            }

        if let maxIndex = tokens.firstIndex(of: "max"),
           maxIndex + 1 < tokens.count,
           tokens[maxIndex + 1].hasSuffix("x") {
            return "Max \(tokens[maxIndex + 1])"
        }

        let words = tokens.isEmpty ? [raw] : tokens
        return words
            .map { token in
                switch token {
                case "prolite": return "Pro Lite"
                case "self": return "Self"
                case "serve": return "Serve"
                case "usage": return "Usage"
                case "based": return "Based"
                default: return token.capitalized
                }
            }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
