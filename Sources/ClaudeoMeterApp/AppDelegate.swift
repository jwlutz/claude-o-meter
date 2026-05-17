import AppKit
import SwiftUI
import Combine
import os
import ClaudeoMeterCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private static let log = Logger(subsystem: "com.claude-o-meter.menubar", category: "ui")

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let store = UsageStore()
    private var cancellable: AnyCancellable?
    private var defaultsObserver: NSObjectProtocol?
    private var pendingRender = false
    private var lastRenderedStatusKey: String?

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
        button.image = nil
        button.title = ""
        button.isBordered = false
        button.target = self
        button.action = #selector(togglePopover(_:))

        popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        let popoverController = NSHostingController(rootView: PopoverView(store: store))
        popoverController.view.wantsLayer = true
        popoverController.view.layer?.backgroundColor = NSColor.clear.cgColor
        popover.contentViewController = popoverController
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
        store.refresh(force: true)
    }

    private func renderStatusItem() {
        guard let button = statusItem.button else { return }
        let snapshot = store.snapshot
        let showTimer = UserDefaults.standard.object(forKey: UsagePreferenceKeys.showTimer) as? Bool ?? true
        let providers = UsagePreferences.enabledProviderIDs()
        let width = MenuBarPillImage.width(providers: providers, showTimer: showTimer)
        let now = Date()
        let appearance = button.effectiveAppearance
        let appearanceKey = statusAppearanceKey(appearance)
        let renderKey = statusRenderKey(
            snapshot: snapshot,
            providers: providers,
            showTimer: showTimer,
            now: now,
            appearanceKey: appearanceKey
        )

        if popover?.isShown == true {
            if abs(statusItem.length - width) > 0.5 || lastRenderedStatusKey != renderKey {
                pendingRender = true
            }
            return
        }
        if button.image != nil,
           abs(statusItem.length - width) <= 0.5,
           lastRenderedStatusKey == renderKey {
            return
        }
        let renderStartedAt = CFAbsoluteTimeGetCurrent()
        let image = MenuBarPillImage.render(
            snapshot: snapshot,
            providers: providers,
            showTimer: showTimer,
            now: now,
            appearance: appearance
        )
        statusItem.length = width
        button.image = image
        button.title = ""
        lastRenderedStatusKey = renderKey
        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - renderStartedAt) * 1000)
        Self.log.debug("Rendered status item in \(elapsedMs, privacy: .public)ms")
    }

    private func statusRenderKey(
        snapshot: UsageSnapshot,
        providers: [UsageProviderID],
        showTimer: Bool,
        now: Date,
        appearanceKey: String
    ) -> String {
        let providerKeys = providers.map { provider in
            let window = primaryWindow(for: provider, in: snapshot)
            let usage = window.map { String(Int($0.usedPercent.rounded())) } ?? "unknown"
            let timer = showTimer ? (window?.resetText(relativeTo: now) ?? "--") : "hidden"
            return "\(provider.rawValue):\(usage):\(timer)"
        }
        return "\(appearanceKey):\(showTimer):\(providers.map(\.rawValue).joined(separator: ",")):\(providerKeys.joined(separator: "|"))"
    }

    private func statusAppearanceKey(_ appearance: NSAppearance) -> String {
        appearance.bestMatch(from: [
            .darkAqua,
            .aqua,
            .vibrantDark,
            .vibrantLight,
            .accessibilityHighContrastDarkAqua,
            .accessibilityHighContrastAqua,
            .accessibilityHighContrastVibrantDark,
            .accessibilityHighContrastVibrantLight,
        ])?.rawValue ?? appearance.name.rawValue
    }

    private func primaryWindow(for provider: UsageProviderID, in snapshot: UsageSnapshot) -> UsageWindow? {
        guard case .subscription(let stats) = snapshot.provider(provider)?.mode else { return nil }
        return stats.primaryWindow
    }

    private func updatePopoverSize() {
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
