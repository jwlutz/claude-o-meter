import Foundation
import ClaudeoMeterCore

enum ProviderProbeResult {
    case ok(ProviderUsageStats)
    case failed(String)
    case transientFailure(String)
}

protocol UsageProvider: AnyObject {
    var id: UsageProviderID { get }
    func run(completion: @escaping (ProviderProbeResult) -> Void)
}

enum UsagePreferenceKeys {
    static let showTimer = "showTimer"
    static let claudeCodeEnabled = "provider.claudeCode.enabled"
    static let codexEnabled = "provider.codex.enabled"
}

enum UsagePreferences {
    static func enabledProviderIDs(defaults: UserDefaults = .standard) -> [UsageProviderID] {
        let providers = UsageProviderID.allCases.filter { provider in
            let key = enabledKey(for: provider)
            guard defaults.object(forKey: key) != nil else { return true }
            return defaults.bool(forKey: key)
        }
        return providers.isEmpty ? UsageProviderID.allCases : providers
    }

    static func enabledKey(for provider: UsageProviderID) -> String {
        switch provider {
        case .claudeCode: return UsagePreferenceKeys.claudeCodeEnabled
        case .codex: return UsagePreferenceKeys.codexEnabled
        }
    }
}
