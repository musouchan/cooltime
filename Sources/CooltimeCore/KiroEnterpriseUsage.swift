import Foundation

/// Exact daily Kiro Enterprise usage exported by Kiro to a customer-controlled S3 bucket.
public enum KiroEnterpriseUsage {
    public struct Configuration: Sendable {
        public let profile: String
        public let region: String
        public let bucket: String
        public let prefix: String
        public let userSelector: String
    }

    private struct Listing: Decodable {
        struct Item: Decodable { let Key: String }
        let Contents: [Item]?
    }

    public static func configuration(from input: String) throws -> Configuration {
        let parts = input.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 5,
              safeToken(parts[0], allowed: ".-_"),
              safeToken(parts[1], allowed: "-"),
              safeBucket(parts[2]),
              safePrefix(parts[3]),
              safeSelector(parts[4]) else { throw invalid() }
        return Configuration(profile: parts[0], region: parts[1], bucket: parts[2],
                             prefix: parts[3], userSelector: parts[4])
    }

    /// Returns only the newest report day and never selects the legacy by_user_analytic export.
    public static func reportKeys(from data: Data) throws -> [String] {
        guard data.count <= 8_000_000,
              let listing = try? JSONDecoder().decode(Listing.self, from: data) else { throw invalid() }
        var byDay: [String: [String]] = [:]
        for item in listing.Contents ?? [] {
            let key = item.Key
            guard key.utf8.count <= 2_048,
                  key.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value != 127 }),
                  key.hasSuffix(".csv") else { continue }
            let parts = key.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard let marker = parts.indices.first(where: {
                $0 + 6 < parts.count && parts[$0] == "KiroLogs" && parts[$0 + 1] == "user_report"
            }) else { continue }
            let year = parts[marker + 3], month = parts[marker + 4], day = parts[marker + 5]
            guard parts[marker + 6] == "00",
                  validDate(year: year, month: month, day: day) else { continue }
            byDay["\(year)-\(month)-\(day)", default: []].append(key)
        }
        guard let newest = byDay.keys.max(), let keys = byDay[newest],
              !keys.isEmpty, keys.count <= 100 else {
            throw ParseError.unsupported("Kiroのuser_report CSVがS3にありません")
        }
        return keys.sorted()
    }

    public static func parse(csvFiles: [Data], userSelector: String, fetchedAt: Date) throws -> Snapshot {
        guard !csvFiles.isEmpty, csvFiles.count <= 100, safeSelector(userSelector),
              csvFiles.reduce(0, { $0 + $1.count }) <= 50_000_000 else { throw invalid() }

        var dateValue: String?
        var seen = Set<String>()
        var planCredits = 0.0
        var overageCredits = 0.0
        var found = false

        for data in csvFiles {
            guard let text = String(data: data, encoding: .utf8) else { throw invalid() }
            let rows = try csv(text)
            guard let header = rows.first, rows.count >= 1 else { throw invalid() }
            let required = ["Date", "UserId", "User_Email", "Client_Type", "Credits_Used",
                            "Overage_Credits_Used", "Overage_Enabled"]
            var index: [String: Int] = [:]
            for name in required {
                guard let i = header.firstIndex(of: name) else { throw invalid() }
                index[name] = i
            }
            for row in rows.dropFirst() where !row.allSatisfy({ $0.isEmpty }) {
                guard row.count == header.count else { throw invalid() }
                let id = row[index["UserId"]!]
                let email = row[index["User_Email"]!]
                guard id == userSelector || email.caseInsensitiveCompare(userSelector) == .orderedSame else { continue }
                let day = row[index["Date"]!]
                guard validDay(day) else { throw invalid() }
                if let dateValue, dateValue != day { throw invalid() }
                dateValue = day
                let client = row[index["Client_Type"]!]
                guard ["KIRO_IDE", "KIRO_CLI", "PLUGIN"].contains(client) else { throw invalid() }
                let fingerprint = day + "|" + id + "|" + client
                guard seen.insert(fingerprint).inserted,
                      let credits = number(row[index["Credits_Used"]!]),
                      let overage = number(row[index["Overage_Credits_Used"]!]),
                      ["true", "false"].contains(row[index["Overage_Enabled"]!].lowercased()) else { throw invalid() }
                planCredits += credits
                overageCredits += overage
                guard validNumber(planCredits), validNumber(overageCredits) else { throw invalid() }
                found = true
            }
        }

        guard found, let dateValue else {
            throw ParseError.unsupported("指定ユーザーのKiro日次利用実績がありません")
        }
        var windows = [
            UsageWindow(label: "Kiro日次利用（\(dateValue)）",
                        reportedAmount: planCredits, reportedUnit: "credits")
        ]
        if overageCredits > 0 {
            windows.append(UsageWindow(label: "Kiro日次オーバーエージ（\(dateValue)）",
                                       reportedAmount: overageCredits, reportedUnit: "credits"))
        }
        return Snapshot(windows: windows, fetchedAt: fetchedAt)
    }

    private static func csv(_ text: String) throws -> [[String]] {
        guard text.utf8.count <= 50_000_000 else { throw invalid() }
        var rows: [[String]] = [], row: [String] = [], field = ""
        var quoted = false, i = text.startIndex
        while i < text.endIndex {
            let ch = text[i]
            if quoted {
                if ch == "\"" {
                    let next = text.index(after: i)
                    if next < text.endIndex && text[next] == "\"" {
                        field.append("\""); i = next
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(ch)
                }
            } else {
                switch ch {
                case "\"":
                    guard field.isEmpty else { throw invalid() }
                    quoted = true
                case ",":
                    row.append(field); field = ""
                case "\n":
                    row.append(field); rows.append(row); row = []; field = ""
                case "\r":
                    break
                default:
                    field.append(ch)
                }
            }
            i = text.index(after: i)
        }
        guard !quoted else { throw invalid() }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        guard rows.count <= 1_000_000 else { throw invalid() }
        return rows
    }

    private static func number(_ value: String) -> Double? {
        guard let result = Double(value), validNumber(result) else { return nil }
        return result
    }

    private static func validNumber(_ value: Double) -> Bool {
        value.isFinite && (0...9_007_199_254_740_991).contains(value)
    }

    private static func validDate(year: String, month: String, day: String) -> Bool {
        validDay("\(year)-\(month)-\(day)")
    }

    private static func validDay(_ value: String) -> Bool {
        guard value.utf8.count == 10 else { return false }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        f.isLenient = false
        return f.date(from: value).map { f.string(from: $0) == value } ?? false
    }

    private static func safeToken(_ value: String, allowed: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128 && value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) ||
            allowed.utf8.contains(byte)
        }
    }

    private static func safeBucket(_ value: String) -> Bool {
        (3...63).contains(value.utf8.count) && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 46
        } && !value.hasPrefix(".") && !value.hasSuffix(".") && !value.contains("..")
    }

    private static func safePrefix(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 512 && !value.hasPrefix("/") &&
        !value.contains("..") && value.utf8.allSatisfy {
            $0 >= 32 && $0 < 127 && $0 != 124 && $0 != 92
        }
    }

    private static func safeSelector(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 320 && value.utf8.allSatisfy {
            $0 >= 32 && $0 < 127 && $0 != 124
        }
    }

    private static func invalid() -> ParseError {
        .unsupported("Kiro EnterpriseのAWS設定または日次利用CSVを確認できません")
    }
}
