import SwiftUI
import ClaudeoMeterCore

enum PopoverMetrics {
    static let width: CGFloat = 420
    static let maxContentHeight: CGFloat = 400

    static func contentSize(snapshot: UsageSnapshot, providers: [UsageProviderID]) -> CGSize {
        CGSize(width: width, height: preferredHeight(snapshot: snapshot, providers: providers))
    }

    private static func preferredHeight(snapshot: UsageSnapshot, providers: [UsageProviderID]) -> CGFloat {
        let chromeHeight: CGFloat = 120
        let providerGap = CGFloat(max(0, providers.count - 1)) * 12
        let contentHeight = providers.reduce(CGFloat.zero) { total, provider in
            total + providerHeight(snapshot.provider(provider))
        } + providerGap
        let scrollHeight = min(contentHeight, maxContentHeight)
        return min(max(chromeHeight + scrollHeight, 240), 560)
    }

    private static func providerHeight(_ snapshot: ProviderUsageSnapshot?) -> CGFloat {
        let rowCount: Int
        if case .subscription(let stats) = snapshot?.mode {
            rowCount = max(1, stats.windows.count)
        } else {
            rowCount = 1
        }

        let headerHeight: CGFloat = 24
        let headerToRows: CGFloat = 10
        let rowHeight: CGFloat = 64
        let dividerSpacing = CGFloat(max(0, rowCount - 1)) * 13
        return headerHeight + headerToRows + CGFloat(rowCount) * rowHeight + dividerSpacing
    }
}

struct PopoverView: View {
    @ObservedObject var store: UsageStore
    @State private var tick = Date()
    @AppStorage(UsagePreferenceKeys.showTimer) private var showTimer: Bool = true
    @AppStorage(UsagePreferenceKeys.claudeCodeEnabled) private var showClaudeCode: Bool = true
    @AppStorage(UsagePreferenceKeys.codexEnabled) private var showCodex: Bool = true
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 8)
            ScrollView {
                content
            }
            .frame(maxHeight: PopoverMetrics.maxContentHeight)
            Divider().padding(.vertical, 8)
            footer
        }
        .padding(16)
        .frame(width: PopoverMetrics.width)
        .onReceive(ticker) { tick = $0 }
        .onAppear { normalizeProviderPreferences() }
        .onChange(of: showClaudeCode) { _ in normalizeProviderPreferences() }
        .onChange(of: showCodex) { _ in normalizeProviderPreferences() }
    }

    private var header: some View {
        HStack {
            Text("Claude-o-Meter").font(.headline)
            Spacer()
            Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(visibleProviderIDs.enumerated()), id: \.element.id) { index, provider in
                ProviderSection(
                    snapshot: store.snapshot.provider(provider) ?? ProviderUsageSnapshot(
                        provider: provider,
                        generatedAt: Date(),
                        mode: .unknown(nil)
                    ),
                    now: tick
                )

                if index < visibleProviderIDs.count - 1 {
                    Divider()
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("Updated \(relativeTime(store.snapshot.generatedAt))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Toggle("Claude", isOn: claudeBinding)
                .toggleStyle(.checkbox)
                .font(.caption)
            Toggle("Codex", isOn: codexBinding)
                .toggleStyle(.checkbox)
                .font(.caption)
            Toggle("Timer", isOn: $showTimer)
                .toggleStyle(.checkbox)
                .font(.caption)
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let s = Int(tick.timeIntervalSince(date))
        if s < 5 { return "just now" }
        if s < 60 { return "\(s)s ago" }
        return "\(s / 60)m ago"
    }

    private var visibleProviderIDs: [UsageProviderID] {
        var providers: [UsageProviderID] = []
        if showClaudeCode { providers.append(.claudeCode) }
        if showCodex { providers.append(.codex) }
        return providers.isEmpty ? UsageProviderID.allCases : providers
    }

    private var claudeBinding: Binding<Bool> {
        Binding(
            get: { showClaudeCode },
            set: { newValue in
                if !newValue && !showCodex { showCodex = true }
                showClaudeCode = newValue
            }
        )
    }

    private var codexBinding: Binding<Bool> {
        Binding(
            get: { showCodex },
            set: { newValue in
                if !newValue && !showClaudeCode { showClaudeCode = true }
                showCodex = newValue
            }
        )
    }

    private func normalizeProviderPreferences() {
        if !showClaudeCode && !showCodex {
            showClaudeCode = true
            showCodex = true
        }
    }
}

private struct ProviderSection: View {
    let snapshot: ProviderUsageSnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(snapshot.provider.displayName)
                    .font(.subheadline.bold())
                Spacer()
                modeBadge
            }

            switch snapshot.mode {
            case .unknown(let reason):
                unknownView(reason: reason)
            case .subscription(let stats):
                ForEach(Array(stats.windows.enumerated()), id: \.element.id) { index, window in
                    if index > 0 { Divider() }
                    UsageWindowRow(provider: snapshot.provider, window: window, now: now)
                }
            }
        }
    }

    @ViewBuilder
    private var modeBadge: some View {
        switch snapshot.mode {
        case .unknown:
            Text("offline").font(.caption2).foregroundStyle(.secondary)
        case .subscription(let stats):
            Text(PlanLabel.display(stats.plan)).font(.caption2.bold())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(tint.opacity(0.22)))
        }
    }

    @ViewBuilder
    private func unknownView(reason: String?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ProviderBadge(provider: snapshot.provider, fraction: 1)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    if reason == nil {
                        ProgressView().controlSize(.small)
                    }
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
            Spacer()
        }
    }

    private var tint: Color {
        switch snapshot.provider {
        case .claudeCode: return .orange
        case .codex: return .green
        }
    }
}

private struct UsageWindowRow: View {
    let provider: UsageProviderID
    let window: UsageWindow
    let now: Date

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ProviderBadge(provider: provider, fraction: window.usedPercent / 100.0)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(window.title).font(.subheadline).foregroundStyle(.secondary)
                Text("\(Int(window.usedPercent.rounded()))% used")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Resets").font(.caption).foregroundStyle(.secondary)
                Text(window.resetText(relativeTo: now) ?? "—")
                    .font(.system(.body, design: .rounded).monospacedDigit())
            }
        }
    }
}
