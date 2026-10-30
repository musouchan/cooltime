import Foundation

public enum ParseError: Error, LocalizedError, Equatable {
    case invalid(String)
    case unsupported(String)
    public var errorDescription: String? {
        switch self {
        case .invalid(let s): return "応答を読み取れませんでした（\(s)）"
        case .unsupported(let s): return s
        }
    }
}

// MARK: - 小さな道具

func json(_ data: Data) throws -> [String: Any] {
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw ParseError.invalid("JSON ではありません")
    }
    return obj
}

func number(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let s = v as? String { return Double(s) }
    return nil
}

/// 数値（秒またはミリ秒の UNIX 時刻）か ISO8601 文字列を Date にする。
func parseDate(_ v: Any?) -> Date? {
    if let n = number(v) {
        return Date(timeIntervalSince1970: n > 1e12 ? n / 1000 : n)
    }
    if let s = v as? String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
    return nil
}

// MARK: - Claude Code ステータスライン

public enum ClaudeStatusline {
    /// ステータスラインに渡される JSON の `rate_limits`（5時間・週）を読む。
    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        let root = try json(data)
        guard let limits = root["rate_limits"] as? [String: Any] else {
            throw ParseError.unsupported("利用枠の情報がありません（Pro / Max 契約のみ対応）")
        }
        var windows: [UsageWindow] = []
        for (key, label) in [("five_hour", "5時間枠"), ("seven_day", "週の枠")] {
            guard let w = limits[key] as? [String: Any], let used = number(w["used_percentage"]) else { continue }
            windows.append(UsageWindow(label: label, usedPercent: used, resetsAt: parseDate(w["resets_at"])))
        }
        guard !windows.isEmpty else { throw ParseError.invalid("5時間枠・週の枠が見つかりません") }
        return Snapshot(windows: windows, fetchedAt: fetchedAt)
    }
}

// MARK: - Codex app-server

public enum CodexRateLimits {
    /// `account/rateLimits/read` の応答（JSON-RPC の1行）を読む。項目名は実機で要確認。
    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        let root = try json(data)
        if let err = root["error"] as? [String: Any] {
            throw ParseError.unsupported("Codex から応答がありませんでした（\(err["message"] as? String ?? "エラー")）")
        }
        guard let result = root["result"] as? [String: Any],
              let limits = (result["rateLimits"] as? [String: Any]) else {
            throw ParseError.invalid("rateLimits がありません")
        }
        var windows: [UsageWindow] = []
        for key in ["primary", "secondary"] {
            guard let w = limits[key] as? [String: Any], let used = number(w["usedPercent"]) else { continue }
            windows.append(UsageWindow(label: label(minutes: number(w["windowDurationMins"])),
                                       usedPercent: used, resetsAt: parseDate(w["resetsAt"])))
        }
        var credit: CreditBalance?
        if let c = limits["credits"] as? [String: Any], (c["hasCredits"] as? Bool) == true,
           let balance = number(c["balance"]) {
            credit = CreditBalance(amount: balance, currency: "credits")
        }
        guard !windows.isEmpty || credit != nil else { throw ParseError.invalid("利用枠が見つかりません") }
        return Snapshot(windows: windows, credit: credit, fetchedAt: fetchedAt)
    }

    static func label(minutes: Double?) -> String {
        guard let m = minutes else { return "利用枠" }
        if abs(m - 300) < 30 { return "5時間枠" }
        if abs(m - 10080) < 600 { return "週の枠" }
        if m >= 40000 { return "月の枠" }
        if m >= 120 { return "\(Int((m / 60).rounded()))時間枠" }
        return "\(Int(m))分枠"
    }
}

// MARK: - 公式 API

public enum ElevenLabs {
    /// GET /v1/user/subscription
    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        let r = try json(data)
        guard let used = number(r["character_count"]), let limit = number(r["character_limit"]), limit > 0 else {
            throw ParseError.invalid("文字数が見つかりません")
        }
        let w = UsageWindow(label: "月の文字数", usedPercent: used / limit * 100,
                            resetsAt: parseDate(r["next_character_count_reset_unix"]))
        return Snapshot(windows: [w], fetchedAt: fetchedAt)
    }
}

public enum Firecrawl {
    /// GET /v2/team/credit-usage
    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        let root = try json(data)
        let r = (root["data"] as? [String: Any]) ?? root
        guard let remaining = number(r["remainingCredits"]) else { throw ParseError.invalid("残りが見つかりません") }
        var used: Double?
        if let plan = number(r["planCredits"]), plan > 0 { used = max(0, (plan - remaining) / plan * 100) }
        let w = UsageWindow(label: "月のクレジット", usedPercent: used, remainingCount: remaining,
                            resetsAt: parseDate(r["billingPeriodEnd"]))
        return Snapshot(windows: [w], fetchedAt: fetchedAt)
    }
}

public enum VercelAIGateway {
    /// GET https://ai-gateway.vercel.sh/v1/credits
    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        let r = try json(data)
        guard let balance = number(r["balance"]) else { throw ParseError.invalid("balance がありません") }
        return Snapshot(credit: CreditBalance(amount: balance, currency: "USD"), fetchedAt: fetchedAt)
    }
}

public enum OpenRouter {
    /// GET /api/v1/key。上限（limit）を設定したキーのみ。
    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        let root = try json(data)
        let r = (root["data"] as? [String: Any]) ?? root
        guard number(r["limit"]) != nil, let remaining = number(r["limit_remaining"]) else {
            throw ParseError.unsupported("上限を設定したキーのみ対応しています")
        }
        let reset = (r["limit_reset"] as? String).flatMap { nextReset($0, after: fetchedAt) }
        return Snapshot(credit: CreditBalance(amount: remaining, currency: "USD", resetsAt: reset), fetchedAt: fetchedAt)
    }

    /// OpenRouter の予算リセットは UTC の 日次=毎日0時 / 週次=月曜0時 / 月次=1日0時。
    public static func nextReset(_ kind: String, after date: Date) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var c = DateComponents(hour: 0, minute: 0, second: 0)
        switch kind {
        case "daily": break
        case "weekly": c.weekday = 2
        case "monthly": c.day = 1
        default: return nil
        }
        return cal.nextDate(after: date, matching: c, matchingPolicy: .nextTime)
    }
}

public enum DeepSeek {
    /// GET /user/balance
    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        let r = try json(data)
        guard let infos = r["balance_infos"] as? [[String: Any]],
              let info = infos.first(where: { ($0["currency"] as? String) == "USD" }) ?? infos.first,
              let total = number(info["total_balance"]) else {
            throw ParseError.invalid("balance_infos がありません")
        }
        return Snapshot(credit: CreditBalance(amount: total, currency: (info["currency"] as? String) ?? "USD"),
                        fetchedAt: fetchedAt)
    }
}
