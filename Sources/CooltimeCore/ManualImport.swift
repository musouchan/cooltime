import Foundation

/// A user-entered observation, not a live account-wide API balance.
public struct ManualObservation: Codable, Equatable, Sendable {
    public let remaining: Double
    public let unit: String
    public let observedAt: Date
    public let resetsAt: Date?
    public let source: String

    public init(remaining: Double, unit: String, observedAt: Date, resetsAt: Date? = nil, source: String, now: Date = Date()) throws {
        guard remaining.isFinite, remaining >= 0 else { throw ManualImportError.invalid("残量は0以上の有限数で入力してください") }
        let cleanUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUnit.isEmpty, cleanUnit.count <= 40 else { throw ManualImportError.invalid("単位がありません（最大40文字）") }
        guard !cleanSource.isEmpty, cleanSource.count <= 300 else { throw ManualImportError.invalid("確認元の記録が必要です（最大300文字）") }
        guard observedAt <= now.addingTimeInterval(300) else { throw ManualImportError.invalid("未来の確認日時は指定できません") }
        if let reset = resetsAt, reset < observedAt { throw ManualImportError.invalid("更新日時が確認日時より前です") }
        self.remaining = remaining
        self.unit = cleanUnit
        self.observedAt = observedAt
        self.resetsAt = resetsAt
        self.source = cleanSource
    }

    public var snapshot: Snapshot {
        Snapshot(credit: CreditBalance(amount: remaining, currency: unit, resetsAt: resetsAt,
                                       note: "手動記録・アカウント全体を保証しません｜確認元: \(source)"),
                 fetchedAt: observedAt)
    }
}

public enum ManualImportError: Error, LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        if case .invalid(let detail) = self { return detail }
        return "CSVが不正です"
    }
}

public enum ManualImport {
    public static let header = "remaining,unit,observed_at,reset_at,source"
    /// CSV columns: remaining, unit, observed_at (ISO 8601 with timezone), reset_at (optional), source.
    /// Each row is an independently verified observation; the caller chooses the latest.
    public static func parseCSV(_ csv: String, now: Date = Date()) throws -> [ManualObservation] {
        let records = try fields(csv)
        guard let head = records.first?.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }) else {
            throw ManualImportError.invalid("CSVが空です")
        }
        let required = ["remaining", "unit", "observed_at", "source"]
        guard required.allSatisfy({ head.contains($0) }), Set(head).count == head.count else {
            throw ManualImportError.invalid("列名は remaining,unit,observed_at,reset_at,source を使用してください")
        }
        let index = Dictionary(uniqueKeysWithValues: head.enumerated().map { ($0.element, $0.offset) })
        func value(_ row: [String], _ name: String) -> String {
            guard let i = index[name], i < row.count else { return "" }
            return row[i].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func date(_ text: String) -> Date? { fractional.date(from: text) ?? iso.date(from: text) }
        var observations: [ManualObservation] = []
        for row in records.dropFirst() where row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            guard row.count == head.count else { throw ManualImportError.invalid("CSVの列数が一致しません") }
            guard let remaining = Double(value(row, "remaining")),
                  let observed = date(value(row, "observed_at")) else {
                throw ManualImportError.invalid("残量または確認日時を解析できません（ISO 8601日時とタイムゾーンを指定）")
            }
            let resetText = value(row, "reset_at")
            let reset: Date?
            if resetText.isEmpty { reset = nil }
            else if let parsed = date(resetText) { reset = parsed }
            else { throw ManualImportError.invalid("更新日時の形式が不正です") }
            observations.append(try ManualObservation(remaining: remaining, unit: value(row, "unit"), observedAt: observed,
                                                     resetsAt: reset, source: value(row, "source"), now: now))
        }
        guard !observations.isEmpty else { throw ManualImportError.invalid("CSVにデータ行がありません") }
        guard observations.count <= 500 else { throw ManualImportError.invalid("一度に取り込めるのは500行までです") }
        return observations
    }

    /// Minimal RFC4180 field parser; supports escaped quotes, commas, and multiline quoted cells.
    private static func fields(_ csv: String) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var index = csv.startIndex
        while index < csv.endIndex {
            let c = csv[index]
            let next = csv.index(after: index)
            if c == "\"" {
                if quoted && next < csv.endIndex && csv[next] == "\"" {
                    field.append("\"")
                    index = csv.index(after: next)
                    continue
                }
                if !quoted && !field.isEmpty { throw ManualImportError.invalid("CSVの引用符の位置が不正です") }
                quoted.toggle()
            } else if c == "," && !quoted {
                row.append(field); field = ""
            } else if (c == "\n" || c == "\r") && !quoted {
                if c == "\r" && next < csv.endIndex && csv[next] == "\n" { index = next }
                row.append(field); field = ""
                if !row.allSatisfy({ $0.isEmpty }) { rows.append(row) }
                row = []
            } else {
                field.append(c)
            }
            index = csv.index(after: index)
        }
        guard !quoted else { throw ManualImportError.invalid("CSVの引用符が閉じられていません") }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            if !row.allSatisfy({ $0.isEmpty }) { rows.append(row) }
        }
        return rows
    }
}
