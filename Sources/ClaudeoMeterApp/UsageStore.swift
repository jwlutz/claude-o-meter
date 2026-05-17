import Foundation
import Combine
import os
import ClaudeoMeterCore

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot = .empty

    private static let log = Logger(subsystem: "com.claude-o-meter.menubar", category: "usage")
    private static let probeInterval: TimeInterval = 60
    private static let publishDebounce: TimeInterval = 0.05
    private static let minimumProviderRefreshInterval: TimeInterval = 5
    private static let maxFailureBackoff: TimeInterval = 300

    private let providers: [UsageProviderID: UsageProvider]
    private var probeTimer: Timer?
    private var publishTimer: Timer?
    private var providerSnapshots: [UsageProviderID: ProviderUsageSnapshot]
    private var inFlight: Set<UsageProviderID> = []
    private var failureCounts: [UsageProviderID: Int] = [:]
    private var nextAllowedProbeAt: [UsageProviderID: Date] = [:]

    init(providers: [UsageProvider] = [ClaudeUsageProvider(), CodexUsageProvider()]) {
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
        self.providerSnapshots = Dictionary(uniqueKeysWithValues: UsageProviderID.allCases.map {
            ($0, ProviderUsageSnapshot(provider: $0, generatedAt: Date(), mode: .unknown(nil)))
        })
        publishSnapshotNow()
        scheduleProbe(after: 1.0)
    }

    deinit {
        probeTimer?.invalidate()
        publishTimer?.invalidate()
    }

    func refresh(force: Bool = false) {
        for id in UsageProviderID.allCases {
            runProbeNow(id, force: force)
        }
    }

    func preferencesChanged() {
        publishSnapshotNow()
    }

    private func scheduleProbe(after delay: TimeInterval? = nil) {
        probeTimer?.invalidate()
        let interval = delay ?? Self.secondsUntilNextMinuteBoundary()
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
                self?.scheduleProbe()
            }
        }
        probeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private static func secondsUntilNextMinuteBoundary(now: Date = Date()) -> TimeInterval {
        let remainder = now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: probeInterval)
        let seconds = probeInterval - remainder
        return max(1, min(probeInterval, seconds))
    }

    private func runProbeNow(_ id: UsageProviderID, force: Bool) {
        guard let provider = providers[id] else { return }
        guard !inFlight.contains(id) else {
            Self.log.debug("Skipping \(id.rawValue, privacy: .public); probe already in flight")
            return
        }

        let startedAt = Date()
        if !force, let nextAllowed = nextAllowedProbeAt[id], startedAt < nextAllowed {
            let waitMs = Int(nextAllowed.timeIntervalSince(startedAt) * 1000)
            Self.log.debug("Skipping \(id.rawValue, privacy: .public); next probe allowed in \(waitMs, privacy: .public)ms")
            return
        }

        inFlight.insert(id)
        Self.log.debug("Starting \(id.rawValue, privacy: .public) probe")
        provider.run { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight.remove(id)
                let mode: UsageMode
                let outcome: String
                switch result {
                case .ok(let stats):
                    mode = .subscription(stats)
                    outcome = "ok"
                    self.failureCounts[id] = 0
                    self.nextAllowedProbeAt[id] = Date().addingTimeInterval(Self.minimumProviderRefreshInterval)
                case .failed(let r):
                    mode = .unknown(r)
                    outcome = "failed"
                    let failures = (self.failureCounts[id] ?? 0) + 1
                    self.failureCounts[id] = failures
                    self.nextAllowedProbeAt[id] = Date().addingTimeInterval(Self.failureBackoff(for: failures))
                case .transientFailure(let r):
                    outcome = "transient"
                    let failures = (self.failureCounts[id] ?? 0) + 1
                    self.failureCounts[id] = failures
                    self.nextAllowedProbeAt[id] = Date().addingTimeInterval(Self.failureBackoff(for: failures))
                    if case .subscription = self.providerSnapshots[id]?.mode {
                        let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                        Self.log.info("\(id.rawValue, privacy: .public) probe finished in \(elapsedMs, privacy: .public)ms: \(outcome, privacy: .public); preserving last successful snapshot")
                        self.publishSnapshotSoon()
                        return
                    }
                    mode = .unknown(r)
                }
                let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                Self.log.info("\(id.rawValue, privacy: .public) probe finished in \(elapsedMs, privacy: .public)ms: \(outcome, privacy: .public)")
                self.providerSnapshots[id] = ProviderUsageSnapshot(provider: id, generatedAt: Date(), mode: mode)
                self.publishSnapshotSoon()
            }
        }
    }

    private static func failureBackoff(for failures: Int) -> TimeInterval {
        min(maxFailureBackoff, pow(2, Double(min(failures, 6))) * minimumProviderRefreshInterval)
    }

    private func publishSnapshotSoon() {
        publishTimer?.invalidate()
        let timer = Timer(timeInterval: Self.publishDebounce, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.publishSnapshotNow() }
        }
        publishTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func publishSnapshotNow() {
        publishTimer?.invalidate()
        publishTimer = nil
        snapshot = UsageSnapshot(
            generatedAt: Date(),
            providers: UsageProviderID.allCases.compactMap { providerSnapshots[$0] }
        )
        Self.log.debug("Published usage snapshot")
    }
}
