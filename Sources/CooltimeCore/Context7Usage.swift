import Foundation

/// Context7's documented GET /api/v2/usage response.
public enum Context7Usage {
    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        let root = try json(data)
        guard let plan = root["plan"] as? String,
              let reset = parseDate(root["usageResetsAt"]),
              let member = root["member"] as? [String: Any],
              let requests = integer(member["requests"]), requests >= 0,
              let included = integer(member["includedInPlan"]), included >= 0,
              let team = root["teamspace"] as? [String: Any],
              let extraRequests = integer(team["extraRequests"]), extraRequests >= 0,
              let extraCost = number(team["extraCostUsd"]), extraCost.isFinite, extraCost >= 0,
              let rawLimit = team["spendingLimitUsd"] else {
            throw ParseError.invalid("plan / usageResetsAt / member / teamspace fields are missing or invalid")
        }

        let spendingLimit: Double?
        if rawLimit is NSNull {
            spendingLimit = nil
        } else if let limit = number(rawLimit), limit.isFinite, limit >= 0 {
            spendingLimit = limit
        } else {
            throw ParseError.invalid("spendingLimitUsd is invalid")
        }

        var windows: [UsageWindow] = []
        if plan == "free", included > 0 {
            windows.append(UsageWindow(label: "月のリクエスト",
                                       usedPercent: min(100, Double(requests) / Double(included) * 100),
                                       remainingCount: Double(max(0, included - requests)),
                                       resetsAt: reset))
        } else {
            windows.append(UsageWindow(label: "本人の月間リクエスト数",
                                       resetsAt: reset,
                                       reportedAmount: Double(requests),
                                       reportedUnit: "requests"))
        }
        windows.append(UsageWindow(label: "Teamspace追加料金",
                                   resetsAt: reset,
                                   reportedAmount: extraCost,
                                   reportedUnit: "USD"))
        if let limit = spendingLimit {
            let used = limit == 0 ? 100 : min(100, extraCost / limit * 100)
            windows.append(UsageWindow(label: "Teamspace追加料金上限", usedPercent: used, resetsAt: reset))
        }
        return Snapshot(windows: windows, fetchedAt: fetchedAt)
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = number(value), number.isFinite, number >= 0,
              number.rounded() == number, number <= Double(Int.max) else { return nil }
        return Int(number)
    }
}
