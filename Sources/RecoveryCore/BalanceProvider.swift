import Foundation

public enum SourceError: Error, Equatable, LocalizedError {
    case notInstalled(String)
    case notAvailable(String)
    case http(Int)
    case unexpectedResponse(String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled(let n): return "\(n) が見つかりません"
        case .notAvailable(let m): return m
        case .http(let c): return c == 401 || c == 403 ? "認証に失敗しました（APIキーを確認してください）" : "通信エラー（\(c)）"
        case .unexpectedResponse(let m): return "想定と違う応答でした: \(m)"
        }
    }
}

public protocol HTTPClient: Sendable {
    func get(_ url: URL, headers: [String: String]) async throws -> Data
}

public struct URLSessionClient: HTTPClient {
    public init() {}
    public func get(_ url: URL, headers: [String: String]) async throws -> Data {
        var req = URLRequest(url: url, timeoutInterval: 15)
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SourceError.http(http.statusCode)
        }
        return data
    }
}

/// 公式APIで残量を返すサービス。呼ぶのは利用者が押したときだけ（自動では呼ばない）。
public enum BalanceProvider: String, Codable, Sendable {
    case elevenLabs, firecrawl, vercelAIGateway, openRouter, deepSeek

    var url: URL {
        switch self {
        case .elevenLabs: return URL(string: "https://api.elevenlabs.io/v1/user/subscription")!
        case .firecrawl: return URL(string: "https://api.firecrawl.dev/v2/team/credit-usage")!
        case .vercelAIGateway: return URL(string: "https://ai-gateway.vercel.sh/v1/credits")!
        case .openRouter: return URL(string: "https://openrouter.ai/api/v1/key")!
        case .deepSeek: return URL(string: "https://api.deepseek.com/user/balance")!
        }
    }

    func headers(key: String) -> [String: String] {
        switch self {
        case .elevenLabs: return ["xi-api-key": key]
        default: return ["Authorization": "Bearer \(key)"]
        }
    }

    public func fetch(apiKey: String, client: HTTPClient) async throws -> SourceResult {
        let data = try await client.get(url, headers: headers(key: apiKey))
        return try parse(data)
    }

    // MARK: - 解析（ネットワークに依存しないのでテストできる）

    public func parse(_ data: Data) throws -> SourceResult {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SourceError.unexpectedResponse("JSONではありません")
        }
        switch self {
        case .elevenLabs:
            guard let used = Self.number(root["character_count"]),
                  let limit = Self.number(root["character_limit"]), limit > 0,
                  let reset = Self.number(root["next_character_count_reset_unix"]) else {
                throw SourceError.unexpectedResponse("文字数の項目がありません")
            }
            let w = WindowStatus(name: "月の文字数", usedPercent: used / limit * 100,
                                 resetsAt: Date(timeIntervalSince1970: reset))
            return SourceResult(windows: [w])

        case .firecrawl:
            let d = (root["data"] as? [String: Any]) ?? root
            guard let remaining = Self.number(d["remainingCredits"]),
                  let end = Self.date(d["billingPeriodEnd"]) else {
                throw SourceError.unexpectedResponse("クレジットの項目がありません")
            }
            var used = remaining > 0 ? 0.0 : 100.0
            if let plan = Self.number(d["planCredits"]), plan > 0 {
                used = min(100, max(0, (plan - remaining) / plan * 100))
            }
            let w = WindowStatus(name: "月のクレジット", usedPercent: used, resetsAt: end,
                                 detail: "残り \(Int(remaining))")
            return SourceResult(windows: [w])

        case .vercelAIGateway:
            guard let balance = Self.decimal(root["balance"]) else {
                throw SourceError.unexpectedResponse("balance がありません")
            }
            return SourceResult(credit: CreditBalance(amount: balance, currency: "USD"))

        case .openRouter:
            let d = (root["data"] as? [String: Any]) ?? root
            guard let remaining = Self.decimal(d["limit_remaining"]) else {
                // 上限を決めていないキーは残額が返らない。数字を作らず、載せない。
                throw SourceError.notAvailable("このキーには残額の上限が設定されていません")
            }
            return SourceResult(credit: CreditBalance(amount: remaining, currency: "USD"))

        case .deepSeek:
            guard let infos = root["balance_infos"] as? [[String: Any]], let first = infos.first,
                  let total = Self.decimal(first["total_balance"]) else {
                throw SourceError.unexpectedResponse("balance_infos がありません")
            }
            return SourceResult(credit: CreditBalance(amount: total, currency: (first["currency"] as? String) ?? "CNY"))
        }
    }

    static func number(_ any: Any?) -> Double? {
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String { return Double(s) }
        return nil
    }

    static func decimal(_ any: Any?) -> Decimal? {
        if let s = any as? String { return Decimal(string: s) }
        if let n = any as? NSNumber { return Decimal(string: n.stringValue) }
        return nil
    }

    static func date(_ any: Any?) -> Date? {
        guard let s = any as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
