import Foundation

/// Devin Enterprise の公式APIから、現在のEnterprise root budgetに対するACU残量を算出する。
/// Consumption APIとBudgets APIはいずれも読み取り専用GETで呼び出す。
public enum DevinEnterpriseUsage {
    public struct Cycle: Equatable, Sendable {
        public let after: Int
        public let before: Int
    }

    public static func currentCycle(in data: Data, now: Date) throws -> Cycle {
        let root = try json(data)
        guard root["has_next_page"] as? Bool != true,
              let items = root["items"] as? [[String: Any]] else {
            throw ParseError.unsupported("請求サイクル一覧を完全に読み取れません")
        }
        let nowEpoch = now.timeIntervalSince1970
        let cycles = items.compactMap { item -> Cycle? in
            guard let after = number(item["after"]), let before = number(item["before"]),
                  after.isFinite, before.isFinite, before > after,
                  after <= nowEpoch, nowEpoch < before else { return nil }
            return Cycle(after: Int(after), before: Int(before))
        }
        guard let current = cycles.max(by: { $0.after < $1.after }) else {
            throw ParseError.unsupported("現在の請求サイクルが見つかりません")
        }
        return current
    }

    public static func rootBudgetLimit(in data: Data) throws -> Double {
        let root = try json(data)
        guard root["has_next_page"] as? Bool != true,
              let items = root["items"] as? [[String: Any]] else {
            throw ParseError.unsupported("予算一覧を完全に読み取れません")
        }
        let roots = items.filter {
            $0["status"] as? String == "active" && ($0["parent_budget_id"] is NSNull)
        }
        guard roots.count == 1, let budget = roots.first else {
            throw ParseError.unsupported("activeなEnterprise root予算を一意に確認できません")
        }
        let effectiveValue = (budget["temporary_cycle_acu_limit"] as? NSNull) == nil
            ? budget["temporary_cycle_acu_limit"] : budget["cycle_acu_limit"]
        guard let limit = number(effectiveValue), limit.isFinite, limit >= 0 else {
            throw ParseError.unsupported("root予算に有限のACU上限が設定されていません")
        }
        return limit
    }

    public static func parse(cyclesData: Data, budgetsData: Data, consumptionData: Data,
                             now: Date, fetchedAt: Date) throws -> Snapshot {
        let cycle = try currentCycle(in: cyclesData, now: now)
        let limit = try rootBudgetLimit(in: budgetsData)
        let usage = try json(consumptionData)
        guard let consumed = number(usage["total_acus"]), consumed.isFinite, consumed >= 0 else {
            throw ParseError.invalid("total_acus がありません")
        }
        let remaining = max(0, limit - consumed)
        let usedPercent = limit == 0 ? 100 : consumed / limit * 100
        return Snapshot(windows: [
            UsageWindow(label: "Enterprise ACU予算", usedPercent: usedPercent,
                        remainingCount: remaining,
                        resetsAt: Date(timeIntervalSince1970: TimeInterval(cycle.before)))
        ], fetchedAt: fetchedAt)
    }
}
