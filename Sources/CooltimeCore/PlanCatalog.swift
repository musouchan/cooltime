import Foundation

/// サービスごとの、プランと、公式の月額（米ドル）の目安。
/// 値上げがあるので、あくまで「目安」。本人が、円で上書きできる（Account.monthlyPrice）。
public struct PlanOption: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let usdMonthly: Int

    public var priceText: String { "月 $\(usdMonthly)" }
}

public enum PlanCatalog {
    public static func options(for serviceID: String) -> [PlanOption] {
        switch serviceID {
        case "claude":
            return [PlanOption(id: "pro", name: "Pro", usdMonthly: 20),
                    PlanOption(id: "max5x", name: "Max 5x", usdMonthly: 100),
                    PlanOption(id: "max20x", name: "Max 20x", usdMonthly: 200)]
        case "codex":
            return [PlanOption(id: "plus", name: "Plus", usdMonthly: 20),
                    PlanOption(id: "pro", name: "Pro", usdMonthly: 200)]
        default:
            return []
        }
    }

    public static func option(serviceID: String, id: String?) -> PlanOption? {
        guard let id else { return nil }
        return options(for: serviceID).first { $0.id == id }
    }

    /// アカウント情報に出てくるプラン名（"Plus"、"pro" など）から、候補を探す。分からなければ nil（作らない）。
    public static func match(serviceID: String, planName: String?) -> PlanOption? {
        guard let key = planName?.lowercased().replacingOccurrences(of: " ", with: "") else { return nil }
        return options(for: serviceID).first { $0.id == key || $0.name.lowercased().replacingOccurrences(of: " ", with: "") == key }
    }
}
