import Foundation

/// Parses the documented v0 Platform API GET /v1/user/plan response.
public enum V0Billing {
    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let balance = root["balance"] as? [String: Any],
              let remaining = number(balance["remaining"]), remaining.isFinite, remaining >= 0 else {
            throw ParseError.invalid("v0 balance.remaining がありません")
        }

        let resetDate: Date?
        if let cycle = root["billingCycle"] as? [String: Any],
           let rawEnd = cycle["end"] {
            guard let end = number(rawEnd), end.isFinite, end > 0 else {
                throw ParseError.invalid("v0 billingCycle.end の形式が不正です")
            }
            resetDate = Date(timeIntervalSince1970: end)
        } else {
            resetDate = nil
        }

        let plan = root["plan"] as? String
        return Snapshot(
            credit: CreditBalance(
                amount: remaining,
                currency: "credits",
                resetsAt: resetDate,
                note: plan.map { "v0 \($0)" }
            ),
            fetchedAt: fetchedAt
        )
    }

    private static func number(_ value: Any?) -> Double? {
        guard let value, !(value is NSNull) else { return nil }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
}
