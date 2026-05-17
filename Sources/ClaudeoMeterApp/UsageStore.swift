import Foundation
import Combine
import ClaudeoMeterCore

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot = .empty

    private let providers: [UsageProviderID: UsageProvider]
    private var probeTimer: Timer?
    private var providerSnapshots: [UsageProviderID: ProviderUsageSnapshot]
    private var inFlight: Set<UsageProviderID> = []

    init(providers: [UsageProvider] = [ClaudeUsageProvider(), CodexUsageProvider()]) {
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
        self.providerSnapshots = Dictionary(uniqueKeysWithValues: UsageProviderID.allCases.map {
            ($0, ProviderUsageSnapshot(provider: $0, generatedAt: Date(), mode: .unknown(nil)))
        })
        publishSnapshot()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refresh()
        }
        probeTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit { probeTimer?.invalidate() }

    func refresh() {
        for id in UsageProviderID.allCases {
            runProbeNow(id)
        }
    }

    func preferencesChanged() {
        publishSnapshot()
    }

    private func runProbeNow(_ id: UsageProviderID) {
        guard !inFlight.contains(id), let provider = providers[id] else { return }
        inFlight.insert(id)
        provider.run { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight.remove(id)
                let mode: UsageMode
                switch result {
                case .ok(let stats):  mode = .subscription(stats)
                case .failed(let r):  mode = .unknown(r)
                }
                self.providerSnapshots[id] = ProviderUsageSnapshot(provider: id, generatedAt: Date(), mode: mode)
                self.publishSnapshot()
            }
        }
    }

    private func publishSnapshot() {
        snapshot = UsageSnapshot(
            generatedAt: Date(),
            providers: UsageProviderID.allCases.compactMap { providerSnapshots[$0] }
        )
    }
}
