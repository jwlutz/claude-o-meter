import Foundation
import ClaudeoMeterCore

enum ProviderProbeResult {
    case ok(ProviderUsageStats)
    case failed(String)
}

protocol UsageProvider: AnyObject {
    var id: UsageProviderID { get }
    func run(completion: @escaping (ProviderProbeResult) -> Void)
}

enum UsagePreferenceKeys {
    static let showTimer = "showTimer"
    static let menuBarProvider = "menuBarProvider"
}

enum UsagePreferences {
    static func orderedProviderIDs(defaults: UserDefaults = .standard) -> [UsageProviderID] {
        let selected = selectedMenuBarProvider(defaults: defaults)
        return [selected] + UsageProviderID.allCases.filter { $0 != selected }
    }

    static func selectedMenuBarProvider(defaults: UserDefaults = .standard) -> UsageProviderID {
        defaults.string(forKey: UsagePreferenceKeys.menuBarProvider)
            .flatMap(UsageProviderID.init(rawValue:))
            ?? defaultMenuBarProvider()
    }

    static func defaultMenuBarProvider() -> UsageProviderID {
        FileManager.default.fileExists(atPath: "/Applications/Codex.app") ? .codex : .claudeCode
    }
}
