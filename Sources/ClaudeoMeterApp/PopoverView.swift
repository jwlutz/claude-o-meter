import SwiftUI
import ClaudeoMeterCore

enum PopoverMetrics {
    static let width: CGFloat = 420
    static let maxContentHeight: CGFloat = 520
    static let minHeight: CGFloat = 220
    static let maxHeight: CGFloat = 560
    static let chromeHeight: CGFloat = 120

    static func contentSize(snapshot: UsageSnapshot, providers: [UsageProviderID]) -> CGSize {
        contentSize(scrollHeight: estimatedScrollHeight(snapshot: snapshot, providers: providers))
    }

    static func contentSize(scrollHeight: CGFloat) -> CGSize {
        let height = min(max(chromeHeight + scrollHeight, minHeight), maxHeight)
        return CGSize(width: width, height: height)
    }

    static func estimatedScrollHeight(snapshot: UsageSnapshot, providers: [UsageProviderID]) -> CGFloat {
        min(contentHeight(snapshot: snapshot, providers: providers), maxContentHeight)
    }

    static func shouldScroll(snapshot: UsageSnapshot, providers: [UsageProviderID]) -> Bool {
        contentHeight(snapshot: snapshot, providers: providers) > maxContentHeight
    }

    private static func contentHeight(snapshot: UsageSnapshot, providers: [UsageProviderID]) -> CGFloat {
        let providerGap: CGFloat = 25
        return providers.reduce(CGFloat.zero) { total, provider in
            total + providerHeight(snapshot.provider(provider), provider: provider)
        } + CGFloat(max(0, providers.count - 1)) * providerGap
    }

    private static func providerHeight(_ snapshot: ProviderUsageSnapshot?, provider: UsageProviderID) -> CGFloat {
        let headerHeight: CGFloat = 20
        let headerToRows: CGFloat = 10

        let rowCount: Int
        if case .subscription(let stats) = snapshot?.mode {
            rowCount = max(1, stats.windows.count)
        } else {
            rowCount = estimatedWindowCount(for: provider)
        }

        let rowHeight: CGFloat = 42
        let extraRowHeight: CGFloat = rowHeight + 21
        return headerHeight
            + headerToRows
            + rowHeight
            + CGFloat(max(0, rowCount - 1)) * extraRowHeight
    }

    private static func estimatedWindowCount(for provider: UsageProviderID) -> Int {
        switch provider {
        case .claudeCode: return 3
        case .codex: return 2
        }
    }
}

struct PopoverView: View {
    @ObservedObject var store: UsageStore
    @State private var tick = Date()
    @AppStorage(UsagePreferenceKeys.showTimer) private var showTimer: Bool = true
    @AppStorage(UsagePreferenceKeys.claudeCodeEnabled) private var showClaudeCode: Bool = true
    @AppStorage(UsagePreferenceKeys.codexEnabled) private var showCodex: Bool = true
    private let ticker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        root
            .onReceive(ticker) { tick = $0 }
            .onAppear {
                normalizeProviderPreferences()
            }
            .onChange(of: showClaudeCode) { _ in normalizeProviderPreferences() }
            .onChange(of: showCodex) { _ in normalizeProviderPreferences() }
    }

    @ViewBuilder
    private var root: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 10) {
                panelContent
            }
        } else {
            panelContent
        }
        #else
        panelContent
        #endif
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 8)
            contentArea
            Divider().padding(.vertical, 8)
            footer
        }
        .padding(16)
        .frame(width: PopoverMetrics.width)
    }

    private var header: some View {
        HStack {
            Text("Claude-o-Meter").font(.headline)
            Spacer()
            Button { store.refresh(force: true) } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .padding(6)
            .liquidGlassControl()
            .help("Refresh usage")
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

    @ViewBuilder
    private var contentArea: some View {
        if PopoverMetrics.shouldScroll(snapshot: store.snapshot, providers: visibleProviderIDs) {
            ScrollView(.vertical, showsIndicators: true) {
                content
            }
            .frame(height: PopoverMetrics.estimatedScrollHeight(snapshot: store.snapshot, providers: visibleProviderIDs))
        } else {
            content
                .frame(height: PopoverMetrics.estimatedScrollHeight(snapshot: store.snapshot, providers: visibleProviderIDs))
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("Updated \(relativeTime(store.snapshot.generatedAt))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer()
            Toggle("Claude", isOn: claudeBinding)
                .toggleStyle(GlassSwitchToggleStyle())
            Toggle("Codex", isOn: codexBinding)
                .toggleStyle(GlassSwitchToggleStyle())
            Toggle("Timer", isOn: $showTimer)
                .toggleStyle(GlassSwitchToggleStyle())
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .liquidGlassChip()
                .fixedSize(horizontal: true, vertical: false)
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

private struct GlassSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 5) {
                switchGlyph(isOn: configuration.isOn)
                configuration.label
                    .font(.caption.weight(.semibold))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .contentShape(Capsule())
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .liquidGlassChip()
        .fixedSize(horizontal: true, vertical: false)
    }

    private func switchGlyph(isOn: Bool) -> some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .strokeBorder(.primary.opacity(isOn ? 0.24 : 0.14), lineWidth: 1)
            Circle()
                .fill(.primary.opacity(isOn ? 0.86 : 0.30))
                .frame(width: 10, height: 10)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(.background)
                        .opacity(isOn ? 1 : 0)
                }
        }
        .frame(width: 23, height: 14)
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
            Text("offline")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .liquidGlassChip()
        case .subscription(let stats):
            Text(PlanLabel.display(stats.plan))
                .font(.caption2.bold())
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .liquidGlassChip()
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
