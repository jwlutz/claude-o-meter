import AppKit
import SwiftUI
import Combine
import ClaudeoMeterCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let store = UsageStore()
    private var cancellable: AnyCancellable?
    private var defaultsObserver: NSObjectProtocol?

    /// Toggling the popover's "Timer" checkbox changes the menu-bar button's
    /// width (countdown text appears/disappears). If we re-render while the
    /// popover is open, NSStatusItem resizes the button mid-interaction and
    /// NSPopover's anchor recalc gets confused — empirically the popover
    /// jumps to the screen edge. Defer all menu-bar updates until the
    /// popover closes; this flag tracks whether one is queued.
    private var pendingRender = false

    /// Bundle ID of the Claude desktop app — used to gate the menu bar
    /// icon's visibility on Claude.app's running state.
    private static let claudeBundleID = "com.anthropic.claudefordesktop"

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)

        popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 360, height: 260)
        popover.contentViewController = NSHostingController(rootView: PopoverView(store: store))

        renderStatusItem()
        updateClaudeAppVisibility()

        cancellable = store.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] (_: UsageSnapshot) in self?.renderStatusItem() }

        // Re-render when the user toggles the popover checkbox.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.renderStatusItem() }
        }

        // Track Claude.app lifecycle so the menu bar icon disappears when
        // Claude.app quits and reappears when it launches. Daemon stays
        // alive in the background (LaunchAgent KeepAlive) — no probe call
        // makes sense without Claude's auth, so we also pause the icon
        // updates from a backed-off snapshot.
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ] {
            workspaceCenter.addObserver(
                self,
                selector: #selector(claudeAppStateChanged(_:)),
                name: name,
                object: nil
            )
        }
    }

    @objc private func claudeAppStateChanged(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication,
              app.bundleIdentifier == Self.claudeBundleID
        else { return }
        updateClaudeAppVisibility()
    }

    /// Hide/show the status item based on Claude.app's running state.
    /// `isVisible` is the documented way to remove the icon from the menu
    /// bar without releasing the NSStatusItem.
    private func updateClaudeAppVisibility() {
        let claudeRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == Self.claudeBundleID
        }
        statusItem?.isVisible = claudeRunning
        if claudeRunning {
            // Auth just came back — refresh immediately instead of waiting
            // up to 60s for the next probe tick.
            store.refresh()
        }
    }

    private func renderStatusItem() {
        // Avoid resizing the anchor button while the popover is shown — the
        // popover would re-anchor mid-frame and flicker / jump.
        if popover?.isShown == true {
            pendingRender = true
            return
        }
        guard let button = statusItem.button else { return }
        let snapshot = store.snapshot
        let showTimer = UserDefaults.standard.object(forKey: "showTimer") as? Bool ?? true

        let fraction: Double
        let label: String?
        switch snapshot.mode {
        case .unknown:
            fraction = 0
            label = nil
        case .subscription(let s):
            fraction = min(1.0, s.fiveHourPct / 100.0)
            label = showTimer ? s.fiveHourResetText : nil
        }

        let img = ClaudeBadgeImage.render(fraction: fraction, pointSize: 22)
        img.isTemplate = false
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

    // MARK: NSPopoverDelegate

    /// Apply any deferred menu-bar render once the popover is no longer
    /// anchored to the button. This is what makes the Timer checkbox feel
    /// "instant" without causing the jump bug.
    func popoverDidClose(_ notification: Notification) {
        if pendingRender {
            pendingRender = false
            renderStatusItem()
        }
    }
}
