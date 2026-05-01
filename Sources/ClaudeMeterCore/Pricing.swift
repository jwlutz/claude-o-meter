import Foundation

public struct ModelPricing: Sendable {
    public let inputPerMtok: Double
    public let outputPerMtok: Double
    public let cacheWritePerMtok: Double
    public let cacheReadPerMtok: Double
}

public enum Pricing {
    // Approximate published Anthropic rates (USD per 1M tokens). Tune as rates change.
    public static let opus = ModelPricing(inputPerMtok: 15, outputPerMtok: 75, cacheWritePerMtok: 18.75, cacheReadPerMtok: 1.50)
    public static let sonnet = ModelPricing(inputPerMtok: 3, outputPerMtok: 15, cacheWritePerMtok: 3.75, cacheReadPerMtok: 0.30)
    public static let haiku = ModelPricing(inputPerMtok: 1, outputPerMtok: 5, cacheWritePerMtok: 1.25, cacheReadPerMtok: 0.10)

    public static func pricing(for model: String?) -> ModelPricing {
        let m = (model ?? "").lowercased()
        if m.contains("opus") { return opus }
        if m.contains("haiku") { return haiku }
        return sonnet
    }

    public static func cost(input: Int, output: Int, cacheCreate: Int, cacheRead: Int, model: String?) -> Double {
        let p = pricing(for: model)
        return (Double(input) * p.inputPerMtok
              + Double(output) * p.outputPerMtok
              + Double(cacheCreate) * p.cacheWritePerMtok
              + Double(cacheRead) * p.cacheReadPerMtok) / 1_000_000.0
    }
}
