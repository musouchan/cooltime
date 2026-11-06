import Foundation

/// Reads only the quota object emitted to a user-configured Antigravity CLI statusline file.
/// The statusline script intentionally excludes transcript paths, prompts, and account identifiers.
public enum AntigravityStatusline {
    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        let root = try json(data)
        let quotas = root["quota"] as? [String: Any] ?? root
        guard !quotas.isEmpty else {
            throw ParseError.invalid("Antigravity quota がありません")
        }

        var windows: [UsageWindow] = []
        for id in quotas.keys.sorted() {
            guard let bucket = quotas[id] as? [String: Any] else {
                throw ParseError.invalid("Antigravity quota の形式が不正です")
            }
            if let rawDisabled = bucket["disabled"] {
                guard let disabled = rawDisabled as? Bool else {
                    throw ParseError.invalid("Antigravity quota disabled の形式が不正です")
                }
                if disabled { continue }
            }

            let reset: Date?
            if let rawReset = bucket["reset_time"], !(rawReset is NSNull) {
                guard let parsed = parseDate(rawReset) else {
                    throw ParseError.invalid("Antigravity quota reset_time の形式が不正です")
                }
                reset = parsed
            } else {
                reset = nil
            }

            if let rawFraction = bucket["remaining_fraction"] {
                guard let fraction = number(rawFraction), fraction.isFinite, (0...1).contains(fraction) else {
                    throw ParseError.invalid("Antigravity remaining_fraction は0〜1の有限数で指定してください")
                }
                windows.append(UsageWindow(label: id, usedPercent: (1 - fraction) * 100, resetsAt: reset))
            } else if let rawAmount = bucket["remaining_amount"] {
                guard let amount = number(rawAmount), amount.isFinite, amount >= 0 else {
                    throw ParseError.invalid("Antigravity remaining_amount は0以上の有限数で指定してください")
                }
                windows.append(UsageWindow(label: id, remainingCount: amount, resetsAt: reset))
            } else {
                throw ParseError.invalid("Antigravity quota に remaining_fraction または remaining_amount がありません")
            }
        }

        guard !windows.isEmpty else {
            throw ParseError.unsupported("Antigravity に有効なモデル別クォータがありません")
        }
        return Snapshot(windows: windows, fetchedAt: fetchedAt)
    }
}
