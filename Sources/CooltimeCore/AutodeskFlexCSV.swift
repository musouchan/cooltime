import Foundation

/// Reads only a user-exported Autodesk Token Usage report, not a generic seat usage export.
public enum AutodeskFlexCSV {
    private static let maximumBytes = 4 * 1_024 * 1_024

    public static func read(configuration: String) throws -> Snapshot {
        let parts = configuration.split(separator: "|", omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty }),
              parts[0].hasPrefix("/"), !parts[0].contains("\0"),
              let attrs = try? FileManager.default.attributesOfItem(atPath: parts[0]),
              let size = attrs[.size] as? NSNumber, size.intValue <= maximumBytes,
              let data = try? Data(contentsOf: URL(fileURLWithPath: parts[0])) else { throw invalid() }
        return try parse(data, team: parts[1], product: parts[2],
                         fetchedAt: (attrs[.modificationDate] as? Date) ?? Date())
    }

    public static func parse(_ data: Data, team: String, product: String, fetchedAt: Date) throws -> Snapshot {
        guard data.count <= maximumBytes, !team.isEmpty, !product.isEmpty,
              let csv = String(data: data, encoding: .utf8) else { throw invalid() }
        let rows = try ManualImport.fields(csv)
        guard let first = rows.first, rows.count > 1 else { throw invalid() }
        let headers = first.map { $0.replacingOccurrences(of: "\u{feff}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard Set(headers).count == headers.count,
              let teamIndex = headers.firstIndex(of: "team"),
              let productIndex = headers.firstIndex(of: "product"),
              let dateIndex = headers.firstIndex(of: "day used"),
              let tokensIndex = headers.firstIndex(of: "tokens used") else { throw invalid() }
        var sum = 0.0
        var matches = 0
        for row in rows.dropFirst() {
            guard row.count == headers.count else { throw invalid() }
            guard row[teamIndex].trimmingCharacters(in: .whitespacesAndNewlines) == team,
                  row[productIndex].trimmingCharacters(in: .whitespacesAndNewlines) == product else { continue }
            guard !row[dateIndex].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let amount = number(row[tokensIndex]) else { throw invalid() }
            sum += amount
            matches += 1
            guard sum.isFinite, sum <= 9_007_199_254_740_991 else { throw invalid() }
        }
        guard matches > 0 else { throw invalid() }
        return Snapshot(windows: [UsageWindow(label: "Autodesk Flex・\(product)（CSV選択期間）",
                                              reportedAmount: sum, reportedUnit: "tokens")],
                        fetchedAt: fetchedAt)
    }

    private static func number(_ raw: String) -> Double? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let groups = text.split(separator: ",", omittingEmptySubsequences: false)
        guard let first = groups.first, !first.isEmpty,
              first.allSatisfy({ $0 >= "0" && $0 <= "9" }),
              groups.dropFirst().allSatisfy({ $0.count == 3 && $0.allSatisfy({ $0 >= "0" && $0 <= "9" }) }),
              let value = Double(groups.joined()), value.isFinite,
              value <= 9_007_199_254_740_991 else { return nil }
        return value
    }

    private static func invalid() -> ParseError {
        .unsupported("Autodesk Token Usage CSVで指定チーム・製品の確定Flex消費を確認できません")
    }
}
