import Foundation

/// 「あと43分」「あと2時間13分」「あと2日5時間」。「明日」「今夜」は使わない。
public func formatRemaining(until: Date, now: Date) -> String {
    let seconds = until.timeIntervalSince(now)
    // 切り上げて、残っているのに「あと0分」と出さない。
    let minutes = max(1, Int((seconds / 60).rounded(.up)))
    if minutes < 60 { return "あと\(minutes)分" }
    if minutes < 24 * 60 {
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "あと\(h)時間" : "あと\(h)時間\(m)分"
    }
    let d = minutes / (24 * 60), h = (minutes % (24 * 60)) / 60
    return h == 0 ? "あと\(d)日" : "あと\(d)日\(h)時間"
}

/// この Mac のタイムゾーンで「18:30」または「11/1 19:02」。
public func formatClock(_ date: Date, now: Date, timeZone: TimeZone = .current) -> String {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = timeZone
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = timeZone
    f.dateFormat = cal.isDate(date, inSameDayAs: now) ? "HH:mm" : "M/d HH:mm"
    return f.string(from: date)
}

public func formatMoney(_ credit: CreditBalance) -> String {
    switch credit.currency {
    case "USD": return String(format: "$%.2f", credit.amount)
    case "CNY": return String(format: "¥%.2f", credit.amount)
    case "credits": return String(format: "%.0f", credit.amount)
    default: return String(format: "%.2f %@", credit.amount, credit.currency)
    }
}
