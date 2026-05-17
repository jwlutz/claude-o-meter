import SwiftUI
import ClaudeoMeterCore

struct PopoverView: View {
    @ObservedObject var store: UsageStore
    @State private var tick = Date()
    @AppStorage(UsagePreferenceKeys.showTimer) private var showTimer: Bool = true
    @AppStorage(UsagePreferenceKeys.menuBarProvider) private var menuBarProviderRaw: String = UsagePreferences.defaultMenuBarProvider().rawValue
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 8)
            ScrollView {
                content
            }
            .frame(maxHeight: 400)
            Divider().padding(.vertical, 8)
            footer
        }
        .padding(16)
        .frame(width: 420)
        .onReceive(ticker) { tick = $0 }
        .onAppear { normalizeProviderPreferences() }
        .onChange(of: menuBarProviderRaw) { _ in normalizeProviderPreferences() }
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
            ForEach(Array(orderedProviderIDs.enumerated()), id: \.element.id) { index, provider in
                ProviderSection(
                    snapshot: store.snapshot.provider(provider) ?? ProviderUsageSnapshot(
                        provider: provider,
                        generatedAt: Date(),
                        mode: .unknown(nil)
                    ),
                    now: tick
                )

                if index < orderedProviderIDs.count - 1 {
                    Divider()
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("Updated \(relativeTime(store.snapshot.generatedAt))")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Toggle("Timer", isOn: $showTimer)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless).font(.caption)
            }

            HStack(spacing: 10) {
                Text("Top")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Top", selection: $menuBarProviderRaw) {
                    ForEach(UsageProviderID.allCases) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
                .labelsHidden()
                .frame(width: 128)

                Spacer()
            }
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let s = Int(tick.timeIntervalSince(date))
        if s < 5 { return "just now" }
        if s < 60 { return "\(s)s ago" }
        return "\(s / 60)m ago"
    }

    private var orderedProviderIDs: [UsageProviderID] {
        let selected = UsageProviderID(rawValue: menuBarProviderRaw) ?? UsagePreferences.defaultMenuBarProvider()
        return [selected] + UsageProviderID.allCases.filter { $0 != selected }
    }

    private func normalizeProviderPreferences() {
        if UsageProviderID(rawValue: menuBarProviderRaw) == nil {
            menuBarProviderRaw = UsagePreferences.defaultMenuBarProvider().rawValue
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
