import Foundation
import Combine
import ClaudeMeterCore

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot = .empty

    private let probe: UsageProbe
    private var probeTimer: Timer?
    private var inFlight = false

    init(probe: UsageProbe = UsageProbe()) {
        self.probe = probe
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.runProbeNow()
        }
        probeTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.runProbeNow() }
        }
    }

    deinit { probeTimer?.invalidate() }

    func refresh() { runProbeNow() }

    private func runProbeNow() {
        if inFlight { return }
        inFlight = true
        probe.run { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight = false
                let mode: UsageMode
                switch result {
                case .ok(let stats):  mode = .subscription(stats)
                case .failed(let r):  mode = .unknown(r)
                }
                self.snapshot = UsageSnapshot(generatedAt: Date(), mode: mode)
            }
        }
    }
}
