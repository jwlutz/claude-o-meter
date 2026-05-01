// Drop this file into an Xcode Widget Extension target.
// It reuses ClaudeMeterCore (UsageReader, UsageSnapshot, Formatting).
// For data sharing across processes, write the snapshot to App Group UserDefaults
// from the menu-bar app, and read it back here. See README "Adding the widget".

#if canImport(WidgetKit)
import WidgetKit
import SwiftUI
import ClaudeMeterCore

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: .empty)
    }
    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(UsageEntry(date: Date(), snapshot: load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let now = Date()
        let entry = UsageEntry(date: now, snapshot: load())
        // Refresh every minute; WidgetKit will throttle.
        let next = now.addingTimeInterval(60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func load() -> UsageSnapshot {
        // Direct read works if widget has the same sandboxed access; otherwise
        // share via App Group: the host app writes snapshot JSON to a shared
        // UserDefaults key, and this provider decodes it. Implement once the
        // App Group is wired in Xcode (see README).
        UsageReader().snapshot()
    }
}

struct ClaudeMeterWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: UsageEntry

    var body: some View {
        switch family {
        case .systemSmall: SmallView(snap: entry.snapshot, now: entry.date)
        case .systemMedium: MediumView(snap: entry.snapshot, now: entry.date)
        default: MediumView(snap: entry.snapshot, now: entry.date)
        }
    }
}

private struct SmallView: View {
    let snap: UsageSnapshot
    let now: Date
    var body: some View {
        VStack(spacing: 6) {
            FilledPie(fraction: snap.fiveHour.fraction)
                .frame(width: 70, height: 70)
            Text("\(Int((snap.fiveHour.fraction * 100).rounded()))%")
                .font(.system(.title3, design: .rounded).bold())
            if let r = snap.fiveHour.timeUntilReset(now: now) {
                Text("resets in \(Formatting.compactDuration(r))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

private struct MediumView: View {
    let snap: UsageSnapshot
    let now: Date
    var body: some View {
        HStack(spacing: 16) {
            cell(title: "5h", usage: snap.fiveHour)
            Divider()
            cell(title: "Week", usage: snap.weekly)
        }
        .padding()
    }
    @ViewBuilder
    private func cell(title: String, usage: WindowUsage) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            FilledPie(fraction: usage.fraction).frame(width: 56, height: 56)
            Text("\(Int((usage.fraction * 100).rounded()))%")
                .font(.system(.headline, design: .rounded))
            if let r = usage.timeUntilReset(now: now) {
                Text(Formatting.compactDuration(r))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

@main
struct ClaudeMeterWidget: Widget {
    let kind: String = "ClaudeMeterWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageProvider()) { entry in
            ClaudeMeterWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Claude Code Usage")
        .description("Track your 5-hour and weekly Claude Code usage.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
#endif
