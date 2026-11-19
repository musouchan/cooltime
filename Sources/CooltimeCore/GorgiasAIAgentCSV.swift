import Foundation

/// Reads the user-exported AI Agent key-metrics CSV, never a ticket export or the Overview report.
public enum GorgiasAIAgentCSV {
    private static let maximumBytes = 2 * 1_024 * 1_024
    private static let metric = "automated interactions"

    public static func read(path: String) throws -> Snapshot {
        let path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.hasPrefix("/"), !path.contains("\0"),
              let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? NSNumber, size.intValue <= maximumBytes,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { throw invalid() }
        let modified = (attrs[.modificationDate] as? Date) ?? Date()
        return try parse(data, fetchedAt: modified)
    }

    public static func parse(_ data: Data, fetchedAt: Date) throws -> Snapshot {
        guard data.count <= maximumBytes, let csv = String(data: data, encoding: .utf8) else { throw invalid() }
        let rows = try ManualImport.fields(csv)
        guard rows.count >= 2 else { throw invalid() }
        let header = rows[0].map(normalize)
        var found: [Double] = []

        // Some exports place metric names in columns; others use metric/value rows.
        if let metricColumn = header.firstIndex(of: metric) {
            guard header.filter({ $0 == metric }).count == 1 else { throw invalid() }
            for row in rows.dropFirst() {
                guard row.count == header.count, let value = count(row[metricColumn]) else { throw invalid() }
                found.append(value)
            }
        } else if let labelColumn = header.firstIndex(where: { ["metric", "name"].contains($0) }),
                  let valueColumn = header.firstIndex(where: { ["value", "count"].contains($0) }) {
            for row in rows.dropFirst() {
                guard row.count == header.count else { throw invalid() }
                if normalize(row[labelColumn]) == metric {
                    guard let value = count(row[valueColumn]) else { throw invalid() }
                    found.append(value)
                }
            }
        } else { throw invalid() }

        // A breakdown or a trend contains multiple rows; summing them could double count.
        guard found.count == 1 else { throw invalid() }
        return Snapshot(windows: [UsageWindow(label: "AI Agent自動処理（CSV選択期間）",
                                              reportedAmount: found[0], reportedUnit: "interactions")],
                        fetchedAt: fetchedAt)
    }

    private static func normalize(_ value: String) -> String {
        value.replacingOccurrences(of: "\u{feff}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func count(_ raw: String) -> Double? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.split(separator: ",", omittingEmptySubsequences: false)
        guard let first = parts.first, !first.isEmpty,
              first.allSatisfy({ $0 >= "0" && $0 <= "9" }),
              parts.dropFirst().allSatisfy({ $0.count == 3 && $0.allSatisfy({ $0 >= "0" && $0 <= "9" }) }),
              let number = Double(parts.joined()), number.isFinite,
              number >= 0, number <= 9_007_199_254_740_991 else { return nil }
        return number
    }

    private static func invalid() -> ParseError {
        .unsupported("Gorgias AI Agentのkey metrics CSVから自動処理件数を一意に確認できません。All Agentsタブのエクスポートを指定してください")
    }
}
