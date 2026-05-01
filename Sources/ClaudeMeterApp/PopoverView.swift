import SwiftUI
import ClaudeMeterCore

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
            Text("ClaudeMeter").font(.headline)
            Spacer()
            modeBadge
            Button { store.refresh(); store.runProbeNow() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private var modeBadge: some View {
        switch store.snapshot.mode {
        case .unknown:
            Text("detecting…").font(.caption2).foregroundStyle(.secondary)
        case .api:
            Text("API").font(.caption2.bold())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(Color.secondary.opacity(0.18)))
        case .subscription(let s):
            Text(prettyPlan(s.plan)).font(.caption2.bold())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(Color.orange.opacity(0.25)))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.snapshot.mode {
        case .unknown: unknownView
        case .api(let s): ApiContent(stats: s)
        case .subscription(let s): SubscriptionContent(stats: s, now: tick)
        }
    }

    private var unknownView: some View {
        HStack {
            ProgressView().controlSize(.small)
            Text("Reading sessions…").foregroundStyle(.secondary)
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

    private func prettyPlan(_ raw: String) -> String {
        switch raw {
        case let s where s.contains("max_20x"): return "Max 20x"
        case let s where s.contains("max_5x"): return "Max 5x"
        case let s where s.contains("pro"): return "Pro"
        case "subscription": return "Subscription"
        default: return raw
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let s = Int(tick.timeIntervalSince(date))
        if s < 5 { return "just now" }
        if s < 60 { return "\(s)s ago" }
        return "\(s / 60)m ago"
    }
}

private struct ApiContent: View {
    let stats: ApiStats

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                FilledPie(fraction: stats.todayBudgetFraction)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today").font(.caption).foregroundStyle(.secondary)
                    Text(Formatting.usd(stats.today.costUSD))
                        .font(.system(.title2, design: .rounded).bold().monospacedDigit())
                    Text("\(stats.today.messages) messages · \(Formatting.compactTokens(stats.today.totalTokens)) tokens")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("of").font(.caption2).foregroundStyle(.secondary)
                    Text(Formatting.usd(stats.dailyBudgetUSD))
                        .font(.system(.callout, design: .rounded).monospacedDigit())
                    Text("daily budget").font(.caption2).foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text("This week").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(Formatting.usd(stats.week.costUSD))
                    .font(.system(.headline, design: .rounded).monospacedDigit())
                Text("·").foregroundStyle(.secondary)
                Text("\(stats.week.messages) msgs")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if !stats.topModels.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("By model (this week)").font(.caption).foregroundStyle(.secondary)
                    ForEach(stats.topModels) { m in
                        HStack {
                            Text(shortModel(m.model)).font(.system(.caption, design: .monospaced))
                            Spacer()
                            Text("\(m.messages)").font(.caption).foregroundStyle(.secondary)
                            Text(Formatting.usd(m.costUSD)).font(.caption.monospacedDigit())
                                .frame(width: 56, alignment: .trailing)
                        }
                    }
                }
            }

            if !stats.topProjects.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("By project (this week)").font(.caption).foregroundStyle(.secondary)
                    ForEach(stats.topProjects) { p in
                        HStack {
                            Text(p.name).font(.caption)
                            Spacer()
                            Text("\(p.messages)").font(.caption).foregroundStyle(.secondary)
                            Text(Formatting.usd(p.costUSD)).font(.caption.monospacedDigit())
                                .frame(width: 56, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    private func shortModel(_ m: String) -> String {
        m.replacingOccurrences(of: "claude-", with: "")
         .replacingOccurrences(of: "-2025", with: "")
    }
}

private struct SubscriptionContent: View {
    let stats: SubscriptionStats
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            row(title: "5-hour window", pct: stats.fiveHourPct, reset: stats.fiveHourResetText)
            Divider()
            row(title: "Weekly", pct: stats.weeklyPct, reset: stats.weeklyResetText)
        }
    }

    @ViewBuilder
    private func row(title: String, pct: Double, reset: String?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            FilledPie(fraction: pct / 100.0).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Text("\(Int(pct.rounded()))% used")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
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
