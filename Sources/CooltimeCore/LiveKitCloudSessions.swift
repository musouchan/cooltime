import CryptoKit
import Foundation

/// LiveKit Cloud Analytics session counts for one project and UTC day.
public enum LiveKitCloudSessions {
    public struct Configuration: Sendable {
        let projectID: String
        let apiKey: String
        let apiSecret: String
    }

    private struct Page: Decodable {
        struct Session: Decodable {
            let sessionId: String
            let createdAt: String
        }
        let sessions: [Session]
    }

    private static let pageSize = 100

    public static func configuration(from value: String) throws -> Configuration {
        let fields = value.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        guard fields.count == 3,
              fields[0].range(of: #"\Ap_[A-Za-z0-9_-]{1,96}\z"#, options: .regularExpression) != nil,
              fields.dropFirst().allSatisfy({ !$0.isEmpty && $0.utf8.count <= 512 && $0.utf8.allSatisfy { (33...126).contains($0) } }) else {
            throw ParseError.unsupported("LiveKit Cloud project ID|API key|API secret の形式で入力してください")
        }
        return Configuration(projectID: fields[0], apiKey: fields[1], apiSecret: fields[2])
    }

    public static func accessToken(config: Configuration, now: Date) throws -> String {
        let header = Data(#"{"alg":"HS256","typ":"JWT"}"#.utf8)
        let time = Int64(now.timeIntervalSince1970)
        let claims = try JSONSerialization.data(withJSONObject: ["iss": config.apiKey, "sub": "cooltime-analytics",
                                                                 "nbf": time - 30, "exp": time + 300,
                                                                 "video": ["roomList": true]])
        let signingInput = "\(base64URL(header)).\(base64URL(claims))"
        let key = SymmetricKey(data: Data(config.apiSecret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(signingInput.utf8), using: key)
        return "\(signingInput).\(base64URL(Data(signature)))"
    }

    public static func fetch(config: Configuration, fetchedAt: Date,
                             get: (String) async throws -> Data) async throws -> Snapshot {
        let day = DailyUsagePeriod.day(fetchedAt.addingTimeInterval(-86_400))
        var sessions = Set<String>()
        let formatter = ISO8601DateFormatter()
        let start = formatter.date(from: "\(day)T00:00:00Z")!
        let end = start.addingTimeInterval(86_400)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for index in 0..<100 {
            let data = try await get(url(config: config, day: day, page: index))
            guard data.count <= 2_000_000, let page = try? JSONDecoder().decode(Page.self, from: data),
                  page.sessions.count <= pageSize else { throw invalid() }
            for session in page.sessions {
                guard !session.sessionId.isEmpty, session.sessionId.utf8.count <= 256,
                      let date = fractional.date(from: session.createdAt) ?? formatter.date(from: session.createdAt),
                      date >= start, date < end, sessions.insert(session.sessionId).inserted else { throw invalid() }
            }
            if page.sessions.count < pageSize {
                return Snapshot(windows: [UsageWindow(label: "LiveKit開始セッション（\(day) UTC）",
                                                     reportedAmount: Double(sessions.count), reportedUnit: "件")],
                                fetchedAt: fetchedAt)
            }
        }
        throw invalid()
    }

    private static func url(config: Configuration, day: String, page: Int) -> String {
        var components = URLComponents(string: "https://cloud-api.livekit.io/api/project/\(config.projectID)/sessions")!
        components.queryItems = [URLQueryItem(name: "start", value: day), URLQueryItem(name: "end", value: day),
                                 URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "limit", value: String(pageSize))]
        return components.string!
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private static func invalid() -> ParseError {
        .unsupported("LiveKit Cloudのセッション実績を全件確認できません")
    }
}
