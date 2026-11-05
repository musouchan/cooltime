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
        if let d = f.date(from: s) { return d }
        // 日付だけ（例: "2026-12-01"）は、その日の0時（UTC）
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(identifier: "UTC")
        day.dateFormat = "yyyy-MM-dd"
        return day.date(from: s)
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
            throw ParseError.unsupported(codexErrorText(err["message"] as? String))
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

    /// Codex のエラー文（英語）を、短い日本語にする。
    static func codexErrorText(_ message: String?) -> String {
        let m = (message ?? "").lowercased()
        if m.contains("error sending request") || m.contains("timed out") || m.contains("connect") || m.contains("dns") {
            return "Codex が ChatGPT に接続できませんでした（通信を確認）"
        }
        if m.contains("401") || m.contains("unauthorized") || m.contains("log in") || m.contains("login") || m.contains("auth") {
            return "ログインの期限切れの可能性があります（ChatGPT アプリで再ログイン）"
        }
        return "Codex から利用枠を取得できませんでした（\(String((message ?? "エラー").prefix(60)))）"
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

// MARK: - 追加のAPI（スプレッドシートの調査どおり。実機で要確認）
//
// 公式の資料を、この開発環境から読めなかったため、入口と項目名は、調査表に書かれたものと、
// 一般に知られている形に基づく。応答の形が違うときは、推測せずに、読み取れなかったことを画面に出す。

public enum StabilityAI {
    /// GET https://api.stability.ai/v1/user/balance → {"credits": 12.5}
    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        let r = try json(data)
        guard let c = number(r["credits"]) else { throw ParseError.invalid("credits がありません") }
        return Snapshot(credit: CreditBalance(amount: c, currency: "credits"), fetchedAt: fetchedAt)
    }
}

public enum LumaAI {
    /// GET https://api.lumalabs.ai/dream-machine/v1/credits → {"credit_balance": 1234}（USD のセント）
    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        let r = try json(data)
        guard let cents = number(r["credit_balance"]) else { throw ParseError.invalid("credit_balance がありません") }
        return Snapshot(credit: CreditBalance(amount: cents / 100, currency: "USD"), fetchedAt: fetchedAt)
    }
}

public enum RunwayAPI {
    /// GET https://api.dev.runwayml.com/v1/organization（Authorization: Bearer、X-Runway-Version）→ {"creditBalance": 1000, ...}
    public static let version = "2024-11-06"
    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        let r = try json(data)
        guard let c = number(r["creditBalance"]) else { throw ParseError.invalid("creditBalance がありません") }
        return Snapshot(credit: CreditBalance(amount: c, currency: "credits"), fetchedAt: fetchedAt)
    }
}

public enum Photoroom {
    /// GET https://image-api.photoroom.com/v1/account（x-api-key）→ {"credits": {"available": 9, "subscription": 10}}
    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        let r = try json(data)
        guard let credits = r["credits"] as? [String: Any], let available = number(credits["available"]) else {
            throw ParseError.invalid("credits.available がありません")
        }
        return Snapshot(credit: CreditBalance(amount: available, currency: "credits"), fetchedAt: fetchedAt)
    }
}

public enum Meshy {
    /// GET https://api.meshy.ai/openapi/v1/balance → {"balance": 1234}。月のリセット時刻の項目があれば、それも使う。
    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        let r = try json(data)
        guard let b = number(r["balance"]) else { throw ParseError.invalid("balance がありません") }
        let reset = ["monthly_resets_at", "monthlyResetsAt", "reset_at"].lazy.compactMap { parseDate(r[$0]) }.first
        return Snapshot(credit: CreditBalance(amount: b, currency: "credits", resetsAt: reset), fetchedAt: fetchedAt)
    }
}

public enum Apify {
    /// GET https://api.apify.com/v2/users/me/limits →
    /// {"data": {"monthlyUsageCycle": {"startAt", "endAt"}, "limits": {"maxMonthlyUsageUsd"}, "current": {"monthlyUsageUsd"}}}
    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        let root = try json(data)
        let r = (root["data"] as? [String: Any]) ?? root
        guard let limits = r["limits"] as? [String: Any], let max = number(limits["maxMonthlyUsageUsd"]), max > 0,
              let current = r["current"] as? [String: Any], let used = number(current["monthlyUsageUsd"]) else {
            throw ParseError.invalid("月の利用額と上限が見つかりません")
        }
        let end = ((r["monthlyUsageCycle"] as? [String: Any])?["endAt"]).flatMap(parseDate)
        let w = UsageWindow(label: "月の利用額", usedPercent: used / max * 100, resetsAt: end)
        return Snapshot(windows: [w], fetchedAt: fetchedAt)
    }
}

public enum SerpAPI {
    /// GET https://serpapi.com/account.json?api_key=… →
    /// {"searches_per_month": N, "this_month_usage": n, "plan_searches_left": m, "plan_renewal_date": "…"}（無い項目は使わない）
    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        let r = try json(data)
        guard let limit = number(r["searches_per_month"]), limit > 0 else { throw ParseError.invalid("searches_per_month がありません") }
        guard let left = number(r["plan_searches_left"]) ?? number(r["this_month_usage"]).map({ limit - $0 }) else {
            throw ParseError.invalid("残りの検索回数がありません")
        }
        let w = UsageWindow(label: "月の検索回数", usedPercent: max(0, min(100, (limit - left) / limit * 100)),
                            remainingCount: max(0, left), resetsAt: parseDate(r["plan_renewal_date"]))
        return Snapshot(windows: [w], fetchedAt: fetchedAt)
    }
}

public enum DeepL {
    /// 無料のキー（":fx" で終わる）は api-free、それ以外は api。
    public static func endpoint(forKey key: String) -> String {
        key.hasSuffix(":fx") ? "https://api-free.deepl.com/v2/usage" : "https://api.deepl.com/v2/usage"
    }

    /// GET /v2/usage（Authorization: DeepL-Auth-Key）→ {"character_count": N, "character_limit": M}。期間の終わりがあれば、それも使う。
    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        let r = try json(data)
        guard let used = number(r["character_count"]), let limit = number(r["character_limit"]) else {
            throw ParseError.invalid("character_count / character_limit がありません")
        }
        guard limit > 0 else { throw ParseError.unsupported("文字数の上限が無いプランは、残りを出せません") }
        let w = UsageWindow(label: "月の文字数", usedPercent: used / limit * 100, remainingCount: max(0, limit - used),
                            resetsAt: parseDate(r["end_time"]))
        return Snapshot(windows: [w], fetchedAt: fetchedAt)
    }
}
