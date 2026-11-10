import CoreFoundation
import Foundation

public enum HeyGen {
    public static let endpoint = "https://api.heygen.com/v3/users/me"

    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        let root = try json(data)
        guard let account = root["data"] as? [String: Any], let type = account["billing_type"] as? String else {
            throw ParseError.invalid("HeyGenの請求種別がありません")
        }

        switch type {
        case "wallet":
            guard let wallet = account["wallet"] as? [String: Any],
                  let currency = wallet["currency"] as? String, ["usd", "credits"].contains(currency),
                  let balance = amount(wallet["remaining_balance"]) else {
                throw ParseError.invalid("HeyGenのウォレット残高を読み取れません")
            }
            return Snapshot(credit: CreditBalance(amount: balance, currency: currency == "usd" ? "USD" : currency),
                            fetchedAt: fetchedAt)
        case "subscription":
            guard let subscription = account["subscription"] as? [String: Any],
                  let pools = subscription["credits"] as? [String: Any] else {
                throw ParseError.invalid("HeyGenのクレジット枠がありません")
            }
            let premium = pools["premium_credits"] as? [String: Any]
            let addOn = pools["add_on_credits"] as? [String: Any]
            let premiumCount = amount(premium?["remaining"]).flatMap(Int.init(exactly:))
            let addOnCount = amount(addOn?["remaining"]).flatMap(Int.init(exactly:))
            guard let primaryCount = premiumCount ?? addOnCount else {
                throw ParseError.invalid("HeyGenのクレジット残数がありません")
            }
            var labels: [String] = []
            if let premiumCount { labels.append("プレミアム \(premiumCount)") }
            if let addOnCount { labels.append("追加 \(addOnCount)") }
            let reset = premiumCount == nil ? nil : parseDate(premium?["resets_at"] as? String)
            return Snapshot(credit: CreditBalance(amount: Double(primaryCount), currency: "credits", resetsAt: reset,
                                                  note: labels.joined(separator: " / ")), fetchedAt: fetchedAt)
        case "usage_based":
            guard let usage = account["usage_based"] as? [String: Any],
                  let current = amount(usage["spending_current_usd"]),
                  let cap = amount(usage["spending_cap_usd"]) else {
                throw ParseError.unsupported("HeyGenの従量課金では、当期の支出と上限が両方ある場合に表示できます")
            }
            return Snapshot(credit: CreditBalance(amount: max(0, cap - current), currency: "USD",
                                                  note: "当期の支出上限まで"), fetchedAt: fetchedAt)
        default:
            throw ParseError.unsupported("未対応のHeyGen請求種別です")
        }
    }

    private static func amount(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        let amount = value.doubleValue
        return amount.isFinite && amount >= 0 ? amount : nil
    }
}
