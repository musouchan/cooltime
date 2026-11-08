import Foundation

public enum DatadogBitsUsage {
    public enum Site: String {
        case us1, us3, us5, eu1, ap1, ap2, uk1
        case us1Federal = "us1-fed"
        case us2Federal = "us2-fed"

        var host: String {
            switch self {
            case .us1: return "api.datadoghq.com"
            case .eu1: return "api.datadoghq.eu"
            case .us1Federal: return "api.ddog-gov.com"
            case .us2Federal: return "api.us2.ddog-gov.com"
            default: return "api.\(rawValue).datadoghq.com"
            }
        }
    }

    private struct UsageSummary: Decodable {
        let ai_credits_bits_assistant_ai_credits_agg_sum: Double
    }

    public static func configuration(from input: String) throws -> (site: Site, apiKey: String, applicationKey: String) {
        let fields = input.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard fields.count == 3, let site = Site(rawValue: fields[0].lowercased()),
              fields.dropFirst().allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy({ (33...126).contains($0) }) }) else {
            throw ParseError.unsupported("Datadogの site|APIキー|Applicationキー を確認してください")
        }
        return (site, fields[1], fields[2])
    }

    public static func url(for site: Site, now: Date) throws -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM"
        var url = URLComponents()
        url.scheme = "https"
        url.host = site.host
        url.path = "/api/v1/usage/summary"
        url.queryItems = [
            URLQueryItem(name: "start_month", value: formatter.string(from: now)),
            URLQueryItem(name: "include_org_details", value: "false"),
            URLQueryItem(name: "include_connected_accounts", value: "false"),
        ]
        guard let value = url.string else { throw ParseError.unsupported("Datadogの取得先を設定できません") }
        return value
    }

    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        guard let summary = try? JSONDecoder().decode(UsageSummary.self, from: data),
              (0...9_007_199_254_740_991).contains(summary.ai_credits_bits_assistant_ai_credits_agg_sum) else {
            throw ParseError.unsupported("DatadogのBits AI Assistant利用実績を読み取れません")
        }
        let window = UsageWindow(label: "Bits AI Assistant 当月（UTC）",
                                 reportedAmount: summary.ai_credits_bits_assistant_ai_credits_agg_sum, reportedUnit: "credits")
        return Snapshot(windows: [window], fetchedAt: fetchedAt)
    }
}
