import Foundation

/// 公式の Claude Code の `claude -p "/usage"` の表示を読む。
/// 例:
///   Current session: 20% used · resets Nov 1 at 5:19pm (Asia/Tokyo)
///   Current week (all models): 3% used · resets Nov 7 at 4:59pm (Asia/Tokyo)
/// 人が読むための表示なので、形が変わったら読めないことを、はっきりエラーにする。
public enum ClaudeUsageText {
    public static func parse(_ text: String, now: Date) throws -> Snapshot {
        var windows: [UsageWindow] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let label: String
            if line.hasPrefix("Current session") {
                label = "5時間枠"
            } else if line.hasPrefix("Current week (all models)") {
                label = "週の枠"
            } else {
                continue
            }
            guard let pct = groups(#"(\d+(?:\.\d+)?)%\s*used"#, line)?[0].flatMap(Double.init) else { continue }
            var resetsAt: Date?
            if let g = groups(#"resets\s+(.+?)\s*\(([^)]+)\)\s*$"#, line), let when = g[0], let tz = g[1] {
                resetsAt = resetDate(when, timeZone: tz, now: now)
            }
            windows.append(UsageWindow(label: label, usedPercent: pct, resetsAt: resetsAt))
        }
        guard !windows.isEmpty else {
            throw ParseError.unsupported("Claude Code の使用量の表示を読み取れませんでした（Pro / Max 契約のみ対応）")
        }
        return Snapshot(windows: windows, fetchedAt: now)
    }

    /// 「Nov 1 at 5:19pm」「5pm」などを、表示されたタイムゾーンで日時にする。年は書かれていないので、
    /// 今に一番近い年（戻り時刻は未来のはず）を選ぶ。
    static func resetDate(_ text: String, timeZone tzID: String, now: Date) -> Date? {
        guard let g = groups(#"^(?:([A-Za-z]{3})[a-z]*\s+(\d{1,2})(?:,\s*\d{4})?\s+at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)$"#,
                             text.trimmingCharacters(in: .whitespaces)),
              var hour = g[2].flatMap(Int.init), let ampm = g[4]?.lowercased() else { return nil }
        let minute = g[3].flatMap(Int.init) ?? 0
        if hour == 12 { hour = 0 }
        if ampm == "pm" { hour += 12 }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: tzID) ?? .current
        var c = cal.dateComponents([.year, .month, .day], from: now)
        c.hour = hour
        c.minute = minute
        c.second = 0

        if let mon = g[0], let day = g[1].flatMap(Int.init) {
            let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
            guard let m = months.firstIndex(of: mon.lowercased()) else { return nil }
            c.month = m + 1
            c.day = day
            guard let d = cal.date(from: c) else { return nil }
            // 12月に「Jan 2」と出たら翌年。
            if d < now.addingTimeInterval(-60 * 86400) { return cal.date(byAdding: .year, value: 1, to: d) }
            return d
        }
        guard let d = cal.date(from: c) else { return nil }
        return d < now.addingTimeInterval(-60) ? cal.date(byAdding: .day, value: 1, to: d) : d
    }

    /// 最初の一致のキャプチャ（一致しなかったグループは nil）。
    static func groups(_ pattern: String, _ s: String) -> [String?]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (1..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: s).map { String(s[$0]) }
        }
    }
}
