import SwiftUI
import ClaudeoMeterCore

struct PopoverView: View {
    @ObservedObject var store: UsageStore
    @State private var tick = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 8)
            content
            Divider().padding(.vertical, 8)
            footer
        }
        .padding(16)
        .frame(width: 360)
        .onReceive(ticker) { tick = $0 }
    }

    private var header: some View {
        HStack {
            Text("Claude-o-Meter").font(.headline)
            Spacer()
            modeBadge
            Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private var modeBadge: some View {
        switch store.snapshot.mode {
        case .unknown:
            Text("offline").font(.caption2).foregroundStyle(.secondary)
        case .subscription(let s):
            Text(prettyPlan(s.plan)).font(.caption2.bold())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(Color.orange.opacity(0.25)))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.snapshot.mode {
        case .unknown(let reason):
            unknownView(reason: reason)
        case .subscription(let s):
            SubscriptionContent(stats: s, now: tick)
        }
    }

    @ViewBuilder
    private func unknownView(reason: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(reason == nil ? "Reading usage…" : "Usage unavailable")
                    .foregroundStyle(.secondary)
            }
            if let reason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("Updated \(relativeTime(store.snapshot.generatedAt))")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless).font(.caption)
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let s = Int(tick.timeIntervalSince(date))
        if s < 5 { return "just now" }
        if s < 60 { return "\(s)s ago" }
        return "\(s / 60)m ago"
    }

    private func prettyPlan(_ raw: String) -> String {
        switch raw {
        case let s where s.contains("max_20x"): return "Max 20x"
        case let s where s.contains("max_5x"):  return "Max 5x"
        case let s where s.contains("pro"):     return "Pro"
        case "subscription":                    return "Subscription"
        default:                                return raw
        }
    }
}

private struct SubscriptionContent: View {
    let stats: SubscriptionStats
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            row(title: "5-hour window", pct: stats.fiveHourPct, reset: stats.fiveHourResetText)
            Divider()
            row(title: "Weekly · all models", pct: stats.weeklyPct, reset: stats.weeklyResetText)
            if let p = stats.weeklySonnetPct {
                Divider()
                row(title: "Weekly · Sonnet", pct: p, reset: stats.weeklySonnetResetText)
            }
            if let p = stats.weeklyOpusPct {
                Divider()
                row(title: "Weekly · Opus", pct: p, reset: stats.weeklyOpusResetText)
            }
        }
    }

    @ViewBuilder
    private func row(title: String, pct: Double, reset: String?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ClaudeBadge(fraction: pct / 100.0)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Text("\(Int(pct.rounded()))% used")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Resets").font(.caption).foregroundStyle(.secondary)
                Text(reset ?? "—")
                    .font(.system(.body, design: .rounded).monospacedDigit())
            }
        }
    }
}
