import Foundation

/// Microsoft Graph v1.0 Copilot report v2: activity, never subscription balance.
public enum Microsoft365CopilotReport {
    public struct Configuration: Sendable {
        public let tenantID: String
        public let principalName: String
    }

    public static let url = "https://graph.microsoft.com/v1.0/copilot/reports/getMicrosoft365CopilotUsageUserDetail(period='D7',version='v2')"

    public static func configuration(from input: String) throws -> Configuration {
        let parts = input.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2,
              parts[0].range(of: #"^[A-Fa-f0-9]{8}(-[A-Fa-f0-9]{4}){3}-[A-Fa-f0-9]{12}$"#, options: .regularExpression) != nil,
              parts[1].utf8.count <= 254, parts[1].split(separator: "@").count == 2,
              parts[1].utf8.allSatisfy({ (33...126).contains($0) && $0 != 124 })
        else { throw invalid() }
        return Configuration(tenantID: parts[0], principalName: parts[1])
    }

    public static func parse(_ data: Data, principalName: String, fetchedAt: Date) throws -> Snapshot {
        guard data.count <= 8_000_000, let text = String(data: data, encoding: .utf8),
              let rows = csv(text), (2...100_000).contains(rows.count) else { throw invalid() }
        let header = rows[0]
        guard Set(header).count == header.count,
              let user = header.firstIndex(of: "User Principal Name"),
              let refresh = header.firstIndex(of: "Report Refresh Date"),
              let count = header.firstIndex(of: "Prompts submitted for all apps"),
              let period = header.firstIndex(of: "Report Period") else { throw invalid() }
        let selected = rows.dropFirst().filter { $0.count == header.count && $0[user].caseInsensitiveCompare(principalName) == .orderedSame }
        guard selected.count == 1, let row = selected.first, row[period] == "7",
              row[refresh].range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              let value = Int(row[count]), value >= 0 else { throw invalid() }
        return Snapshot(windows: [UsageWindow(label: "Microsoft 365 Copilot・7日間（更新 \(row[refresh])）",
                                              reportedAmount: Double(value), reportedUnit: "prompts")],
                        fetchedAt: fetchedAt)
    }

    /// RFC-style CSV quoting; reject incomplete quotes and inconsistent rows instead of showing partial totals.
    private static func csv(_ text: String) -> [[String]]? {
        var rows: [[String]] = [], row: [String] = [], field = ""
        var quoted = false, closed = false
        // Swift Character treats CRLF as one grapheme; normalize before field scanning.
        let chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n"))
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 }
                    else { quoted = false; closed = true }
                } else { field.append(c) }
            } else if c == "\"" {
                guard field.isEmpty && !closed else { return nil }
                quoted = true
            } else if c == "," || c == "\n" {
                row.append(field); field = ""; closed = false
                if c == "\n" { rows.append(row); row = [] }
            } else {
                guard !closed else { return nil }
                field.append(c)
            }
            i += 1
        }
        guard !quoted else { return nil }
        if !row.isEmpty || !field.isEmpty { row.append(field); rows.append(row) }
        guard let width = rows.first?.count, width > 0, rows.allSatisfy({ $0.count == width }) else { return nil }
        return rows
    }

    private static func invalid() -> ParseError {
        .unsupported("Microsoft 365 Copilotの指定ユーザー利用レポートを確認できません")
    }
}
