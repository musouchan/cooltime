import Foundation

/// Exa Team Management API's read-only team credit balance endpoint.
public enum ExaCredits {
    /// GET https://admin-api.exa.ai/team-management/credits
    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        let root = try json(data)
        guard let balance = number(root["credits_usd"]), balance >= 0 else {
            throw ParseError.invalid("credits_usd がありません")
        }
        return Snapshot(credit: CreditBalance(amount: balance, currency: "USD"), fetchedAt: fetchedAt)
    }
}
