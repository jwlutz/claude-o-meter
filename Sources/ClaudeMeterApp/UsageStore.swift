import Foundation
import Combine
import ClaudeMeterCore

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot = .empty

    private let reader: UsageReader
    private let probe: UsageProbe
    private let parseQueue = DispatchQueue(label: "ClaudeMeter.parse", qos: .utility)
    private var refreshInFlight = false

    private var timer: Timer?
    private var probeTimer: Timer?
    private var fsSource: DispatchSourceFileSystemObject?
    private var watchedFD: Int32 = -1
    private var subscriptionStats: SubscriptionStats?

    init(reader: UsageReader = UsageReader(), probe: UsageProbe = UsageProbe()) {
        self.reader = reader
        self.probe = probe
        refresh()
        startTimer()
        startWatching()
        startProbeLoop()
    }

    deinit {
        timer?.invalidate()
        probeTimer?.invalidate()
        fsSource?.cancel()
        if watchedFD >= 0 { close(watchedFD) }
    }

    func refresh() {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        let reader = self.reader
        let cachedSub = self.subscriptionStats
        parseQueue.async { [weak self] in
            let api = reader.apiStats()
            let mode: UsageMode
            if let s = cachedSub, Date().timeIntervalSince(s.queriedAt) < 5 * 60 {
                mode = .subscription(s)
            } else {
                mode = .api(api)
            }
            let snap = UsageSnapshot(generatedAt: Date(), mode: mode)
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshInFlight = false
                if snap != self.snapshot { self.snapshot = snap }
            }
        }
    }

    func runProbeNow() {
        probe.run { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.subscriptionStats = result
                self.refresh()
            }
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func startProbeLoop() {
        // Run an initial probe a few seconds after launch so we don't block startup.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.runProbeNow()
        }
        probeTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.runProbeNow() }
        }
    }

    private func startWatching() {
        let path = reader.projectsRoot.path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        watchedFD = fd
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .rename, .delete],
            queue: .main
        )
        src.setEventHandler { [weak self] in self?.refresh() }
        src.setCancelHandler { [weak self] in
            if let fd = self?.watchedFD, fd >= 0 { close(fd) }
            self?.watchedFD = -1
        }
        src.resume()
        fsSource = src
    }
}
