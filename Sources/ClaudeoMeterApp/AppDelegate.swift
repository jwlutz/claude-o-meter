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
    private var pendingRender = false

    /// Bundle IDs for provider desktop apps. App lifecycle changes are used as
    /// a refresh hint, but the menu-bar item stays visible so the user can
    /// inspect each provider's current status.
    private static let providerBundleIDs: Set<String> = [
        "com.anthropic.claudefordesktop",
        "com.openai.codex",
    ]

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
        popover.contentViewController = NSHostingController(rootView: PopoverView(store: store))
        updatePopoverSize()

        renderStatusItem()
        store.refresh()

        cancellable = store.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] (_: UsageSnapshot) in
                self?.updatePopoverSize()
                self?.renderStatusItem()
            }

        // Re-render when the user toggles the popover checkbox.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.store.preferencesChanged()
                self?.updatePopoverSize()
                self?.renderStatusItem()
            }
        }

        // Track provider app lifecycle and refresh when auth surfaces come and
        // go. Codex may still be probeable via its CLI while the app is closed.
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ] {
            workspaceCenter.addObserver(
                self,
                selector: #selector(providerAppStateChanged(_:)),
                name: name,
                object: nil
            )
        }
    }

    @objc private func providerAppStateChanged(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication,
              let bundleIdentifier = app.bundleIdentifier,
              Self.providerBundleIDs.contains(bundleIdentifier)
        else { return }
        store.refresh()
    }

    private func renderStatusItem() {
        guard let button = statusItem.button else { return }
        let snapshot = store.snapshot
        let showTimer = UserDefaults.standard.object(forKey: UsagePreferenceKeys.showTimer) as? Bool ?? true
        let providers = UsagePreferences.enabledProviderIDs()

        let img = MenuBarPillImage.render(snapshot: snapshot, providers: providers, showTimer: showTimer)
        img.isTemplate = false
        if popover?.isShown == true, abs(statusItem.length - img.size.width) > 0.5 {
            pendingRender = true
            return
        }
        statusItem.length = img.size.width
        button.image = img
        button.title = ""
    }

    private func updatePopoverSize() {
        guard let popover else { return }
        popover.contentSize = PopoverMetrics.contentSize(
            snapshot: store.snapshot,
            providers: UsagePreferences.enabledProviderIDs()
        )
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            updatePopoverSize()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            store.refresh()
        }
    }

    // MARK: NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        if pendingRender {
            pendingRender = false
            renderStatusItem()
        }
    }
}
