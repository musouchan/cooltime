import Foundation

public enum LangSmithUsage {
    public enum Region: String {
        case us, eu
        var host: String {
            switch self {
            case .us: return "api.smith.langchain.com"
            case .eu: return "eu.api.smith.langchain.com"
            }
        }
    }

    private struct GranularUsage: Decodable {
        struct Stride: Decodable { let days: Int; let hours: Int }
        struct Bucket: Decodable {
            struct Dimensions: Decodable { let workspace_id: UUID }
            let time_bucket: String
            let dimensions: Dimensions
            let traces: Int64
        }
        let stride: Stride
        let usage: [Bucket]
    }

    public static func configuration(from input: String) throws -> (region: Region, workspace: UUID, apiKey: String) {
        let fields = input.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard fields.count == 3, let region = Region(rawValue: fields[0]),
              let workspace = UUID(uuidString: fields[1]), !fields[2].isEmpty,
              fields[2].utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw ParseError.unsupported("region|ワークスペースUUID|APIキー の形式で入力してください")
        }
        return (region, workspace, fields[2])
    }

    public static func period(endingBefore now: Date) -> DateInterval {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let end = utc.startOfDay(for: now)
        return DateInterval(start: end.addingTimeInterval(-7 * 86_400), end: end)
    }

    public static func url(for region: Region, workspace: UUID, period: DateInterval) throws -> String {
        var url = URLComponents()
        url.scheme = "https"
        url.host = region.host
        url.path = "/api/v1/orgs/current/billing/granular-usage"
        let date = ISO8601DateFormatter()
        url.queryItems = [
            URLQueryItem(name: "start_time", value: date.string(from: period.start)),
            URLQueryItem(name: "end_time", value: date.string(from: period.end)),
            URLQueryItem(name: "workspace_ids", value: workspace.uuidString.lowercased()),
            URLQueryItem(name: "group_by", value: "workspace"),
            URLQueryItem(name: "kind", value: "traces"),
        ]
        guard let value = url.string else { throw ParseError.unsupported("LangSmithの取得先を設定できません") }
        return value
    }

    public static func parse(_ data: Data, workspace: UUID, period: DateInterval, fetchedAt: Date) throws -> Snapshot {
        guard let response = try? JSONDecoder().decode(GranularUsage.self, from: data),
              response.stride.days == 1, response.stride.hours == 0, !response.usage.isEmpty else {
            throw ParseError.unsupported("LangSmithの利用実績がありません。ワークスペースと権限を確認してください")
        }
        let iso = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let limit: Int64 = 9_007_199_254_740_991
        var seen = Set<Date>()
        var count: Int64 = 0
        for bucket in response.usage {
            guard bucket.dimensions.workspace_id == workspace,
                  let time = iso.date(from: bucket.time_bucket) ?? fractional.date(from: bucket.time_bucket),
                  time >= period.start, time < period.end,
                  time.timeIntervalSince(period.start).truncatingRemainder(dividingBy: 86_400) == 0,
                  seen.insert(time).inserted,
                  (0...limit - count).contains(bucket.traces) else {
                throw ParseError.unsupported("LangSmithの集計期間またはトレース数を読み取れません")
            }
            count += bucket.traces
        }
        let window = UsageWindow(label: "直近7 UTC日（当日除く）", reportedAmount: Double(count), reportedUnit: "トレース")
        return Snapshot(windows: [window], fetchedAt: fetchedAt)
    }
}
