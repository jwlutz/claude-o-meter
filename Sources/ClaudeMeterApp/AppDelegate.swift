import AppKit
import SwiftUI
import Combine
import ClaudeMeterCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let store = UsageStore()
    private var cancellable: AnyCancellable?
    private var displayTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)

        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 260)
        popover.contentViewController = NSHostingController(rootView: PopoverView(store: store))

        renderStatusItem()

        cancellable = store.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.renderStatusItem() }

        displayTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.renderStatusItem() }
        }
    }

    private func renderStatusItem() {
        guard let button = statusItem.button else { return }
        let snapshot = store.snapshot

        let fraction: Double
        let label: String?
        switch snapshot.mode {
        case .unknown:
            fraction = 0
            label = nil
        case .api(let s):
            fraction = s.todayBudgetFraction
            label = Formatting.usdCompact(s.today.costUSD)
        case .subscription(let s):
            fraction = min(1.0, s.fiveHourPct / 100.0)
            label = s.fiveHourResetText
        }

        let img = ClaudeBadgeImage.render(fraction: fraction, pointSize: 22)
        img.isTemplate = false  // keep our colors; menu bar won't auto-tint
        button.image = img
        button.title = label.map { "  \($0)" } ?? ""
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            store.refresh()
        }
    }
}
