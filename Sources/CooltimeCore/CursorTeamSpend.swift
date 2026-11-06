import CoreFoundation
import Foundation

/// Cursor Teams official Admin API: /teams/spend.
/// Spending is not remaining quota. Never infer a reset time or account balance.
public enum CursorTeamSpend {
    public static let endpoint = "https://api.cursor.com/teams/spend"
    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let members = root["teamMemberSpend"] as? [[String: Any]] else {
            throw ParseError.invalid("Cursor Teams: teamMemberSpend がありません")
        }
        if let pagination = root["pagination"] as? [String: Any],
           (pagination["hasNextPage"] as? Bool) == true {
            throw ParseError.unsupported("Cursor Teams: 次ページがあるため部分的な支出は表示しません")
        }
        var cents = 0.0
        for member in members {
            guard let value = member["overallSpendCents"] as? NSNumber,
                  CFGetTypeID(value) != CFBooleanGetTypeID() else {
                throw ParseError.invalid("Cursor Teams: overallSpendCents が欠損しています")
            }
            let amount = value.doubleValue
            guard amount.isFinite, amount >= 0 else {
                throw ParseError.invalid("Cursor Teams: 支出額が不正です")
            }
            cents += amount
        }
        guard cents.isFinite else { throw ParseError.invalid("Cursor Teams: 支出額が不正です") }
        let dollars = cents / 100
        let label = String(format: "チーム全体の当期支出 $%.2f（残量ではありません）", dollars)
        return Snapshot(windows: [UsageWindow(label: label, resetsAt: nil)], fetchedAt: fetchedAt)
    }
}
