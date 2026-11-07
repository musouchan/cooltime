import Foundation

/// Official metering totals for the authenticated Composio project.
public enum ComposioProjectUsage {
    private struct Response: Decodable {
        struct Entity: Decodable {
            let unit: String
            let total_quantity: String
            let event_count: Int
        }
        let entities: [String: Entity]
    }

    public static func requestBody(now: Date) throws -> Data {
        let period = DailyUsagePeriod.previousSevenDays(now: now, lagHours: 0)
        return try JSONSerialization.data(withJSONObject: [
            "from": Int64(period.start.timeIntervalSince1970 * 1000),
            "to": Int64(period.end.timeIntervalSince1970 * 1000)
        ])
    }

    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        guard data.count <= 1_000_000,
              let response = try? JSONDecoder().decode(Response.self, from: data),
              (1...100).contains(response.entities.count) else { throw invalid() }
        var windows: [UsageWindow] = []
        for (name, entity) in response.entities.sorted(by: { $0.key < $1.key }) {
            guard !name.isEmpty, name.utf8.count <= 128,
                  !entity.unit.isEmpty, entity.unit.utf8.count <= 64,
                  entity.event_count >= 0, entity.total_quantity.count <= 64,
                  let amount = Double(entity.total_quantity), amount.isFinite,
                  amount >= 0, amount <= 9_007_199_254_740_991 else { throw invalid() }
            windows.append(UsageWindow(label: "Composio・\(name)（直近7 UTC日）",
                                       reportedAmount: amount, reportedUnit: entity.unit))
        }
        return Snapshot(windows: windows, fetchedAt: fetchedAt)
    }

    private static func invalid() -> ParseError {
        .unsupported("Composioプロジェクトの公式メータリング情報を確認できません")
    }
}
