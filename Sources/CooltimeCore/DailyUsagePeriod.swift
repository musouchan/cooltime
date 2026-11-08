import Foundation

/// UTC calendar days, inclusive in the API and exclusive at `end` internally.
public struct DailyUsagePeriod: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public var firstDay: String { Self.day(start) }
    public var lastDay: String { Self.day(end.addingTimeInterval(-86_400)) }
    public var label: String { "\(firstDay)〜\(lastDay) UTC" }

    public static func previousSevenDays(now: Date, lagHours: Double) -> Self {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let end = calendar.startOfDay(for: now.addingTimeInterval(-lagHours * 3600))
        return Self(start: end.addingTimeInterval(-7 * 86_400), end: end)
    }

    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func contains(_ value: String) -> Bool {
        (0..<7).contains { Self.day(start.addingTimeInterval(Double($0) * 86_400)) == value }
    }
}

/// Configuration stays in the existing Keychain field, not in account metadata.
enum UsageCredentials {
    static func parse(_ input: String) throws -> (email: String, token: String) {
        let fields = input.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard fields.count == 2, fields[0].count <= 254,
              fields[0].split(separator: "@", omittingEmptySubsequences: false).count == 2,
              !fields[0].hasPrefix("@"), !fields[0].hasSuffix("@"),
              fields.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (33...126).contains($0) } }) else {
            throw ParseError.unsupported("対象メールアドレス|トークン の形式で入力してください")
        }
        return (fields[0], fields[1])
    }
}
