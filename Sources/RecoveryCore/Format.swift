import Foundation

public enum RemainingFormat {
    /// 「あと43分」「あと2時間13分」「あと2日5時間」。「明日」は使わない。
    public static func text(until target: Date, now: Date) -> String {
        let seconds = max(0, Int(target.timeIntervalSince(now)))
        let minutes = max(1, (seconds + 59) / 60) // 切り上げ。0分とは出さない
        if minutes < 60 { return "あと\(minutes)分" }
        if minutes < 24 * 60 {
            let h = minutes / 60, m = minutes % 60
            return m == 0 ? "あと\(h)時間" : "あと\(h)時間\(m)分"
        }
        let d = minutes / (24 * 60), h = (minutes % (24 * 60)) / 60
        return h == 0 ? "あと\(d)日" : "あと\(d)日\(h)時間"
    }

    /// 端末のタイムゾーンで「18:30 ごろ」。
    public static func clock(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.timeZone = timeZone
        f.dateFormat = "H:mm"
        return f.string(from: date) + " ごろ"
    }
}

public enum Aggregator {
    /// メニューバーに出す「一番早く戻るもの」。制限中が無ければ nil（アプリのアイコンだけ出す）。
    public static func earliestRecovery(_ snapshots: [Snapshot], now: Date) -> Date? {
        snapshots.compactMap { snap -> Date? in
            if case let .limited(at) = snap.state(at: now) { return at }
            return nil
        }.min()
    }
}
