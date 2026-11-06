import Foundation

/// Make's documented Organization Usage API; reports the preceding 30 days only.
public enum MakeUsage {
    public struct Configuration: Equatable, Sendable {
        public let region: String
        public let organizationID: String
        public let token: String
    }

    private static let hosts: [String: String] = [
        "eu1": "eu1.make.com",
        "eu2": "eu2.make.com",
        "us1": "us1.make.com",
        "us2": "us2.make.com"
    ]

    /// The API token is stored in Keychain together with its region and organization selector.
    /// Format: region|organizationID|token
    public static func configuration(from value: String) throws -> Configuration {
        let parts = value.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 3 else { throw ParseError.invalid("region|organizationId|token形式で入力してください") }
        let region = String(parts[0])
        let organizationID = String(parts[1])
        let token = String(parts[2])
        guard hosts[region] != nil, !organizationID.isEmpty,
              organizationID.allSatisfy(\.isNumber), organizationID != "0",
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ParseError.invalid("Makeのregion、organizationIdまたはtokenが正しくありません")
        }
        return Configuration(region: region, organizationID: organizationID, token: token)
    }

    public static func usageURL(region: String, organizationID: String) throws -> String {
        guard let host = hosts[region], !organizationID.isEmpty,
              organizationID.allSatisfy(\.isNumber), organizationID != "0" else {
            throw ParseError.invalid("MakeのregionまたはorganizationIdが正しくありません")
        }
        return "https://\(host)/api/v2/organizations/\(organizationID)/usage?organizationTimezone=true"
    }

    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        let root = try json(data)
        guard let rows = root["data"] as? [[String: Any]] else {
            throw ParseError.invalid("dataがありません")
        }
        var total: Double = 0
        for row in rows {
            guard let centicredits = number(row["centicredits"]),
                  centicredits.isFinite, centicredits >= 0 else {
                throw ParseError.invalid("centicreditsがありません")
            }
            total += centicredits
            guard total.isFinite else { throw ParseError.invalid("centicreditsの合計が範囲外です") }
        }
        return Snapshot(windows: [
            UsageWindow(label: "直近30日の消費実績", reportedAmount: total, reportedUnit: "centicredits")
        ], fetchedAt: fetchedAt)
    }
}
