import Foundation

/// 1つの枠の、1回分の期間（リセットからリセットまで）の記録。
public struct WindowPeriod: Codable, Equatable, Sendable {
    public var account: UUID
    public var serviceID: String
    public var label: String
    /// この期間が終わる（リセットされる）時刻。公式の値。
    public var resetsAt: Date
    /// 期間中に見えた、一番大きい使用%。
    public var peakUsed: Double
    public var firstSeen: Date
    public var lastSeen: Date
    /// この期間に、使い切った（制限に当たった）か。
    public var hitLimit: Bool

    /// リセットの直前まで見えていたか。見えていなければ、使い残しは分からない（数字を作らない）。
    public var observedToEnd: Bool { lastSeen >= resetsAt.addingTimeInterval(-6 * 3600) }
    /// リセットの時点で残っていた%。分からないときは nil。
    public var unused: Double? { observedToEnd ? max(0, 100 - peakUsed) : nil }
}

/// 制限に当たった1回。
public struct LimitEvent: Codable, Equatable, Sendable {
    public var account: UUID
    public var serviceID: String
    public var label: String
    public var start: Date
    /// 公式の戻り時刻。
    public var until: Date
}

/// 1時間ごとの「使った量」。週（または月）の枠の使用%が、その1時間に何ポイント増えたか。
/// 増えたことに気づいた時刻（取得した時刻）で、集計する。
public struct UsageBucket: Codable, Equatable, Sendable {
    public var account: UUID
    public var serviceID: String
    /// その時間の始まり（UNIX 時刻の、1時間ごとの区切り）。
    public var hour: Date
    public var points: Double
}

/// 使用状況の記録。Mac の中だけに保存する。会話の中身は持たない（枠の%と時刻だけ）。
public struct UsageHistory: Codable, Equatable, Sendable {
    public var startedAt: Date
    public var periods: [WindowPeriod] = []
    public var limits: [LimitEvent] = []
    /// まだ終わっていない期間（アカウントと枠ごと）。
    public var open: [String: WindowPeriod] = [:]
    /// 時間ごとの使用量（棒グラフ用）。
    public var buckets: [UsageBucket] = []

    public init(startedAt: Date) {
        self.startedAt = startedAt
    }

    private enum CodingKeys: String, CodingKey { case startedAt, periods, limits, open, buckets }

    /// 古い記録（buckets が無いもの）も、そのまま読めるようにする。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        periods = try c.decodeIfPresent([WindowPeriod].self, forKey: .periods) ?? []
        limits = try c.decodeIfPresent([LimitEvent].self, forKey: .limits) ?? []
        open = try c.decodeIfPresent([String: WindowPeriod].self, forKey: .open) ?? [:]
        buckets = try c.decodeIfPresent([UsageBucket].self, forKey: .buckets) ?? []
    }

    /// 時間あたりの使用量を数える枠。5時間枠のように短く戻る枠は、数えない
    /// （週や月の枠に対する%で、サービスをまたいで比べられるようにするため）。
    public static func isBudgetWindow(_ label: String) -> Bool {
        !label.contains("時間") && !label.contains("分")
    }

    mutating func addBucket(account: UUID, serviceID: String, at time: Date, points: Double) {
        guard points > 0 else { return }
        let hour = Date(timeIntervalSince1970: (time.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
        if let i = buckets.firstIndex(where: { $0.account == account && $0.serviceID == serviceID && $0.hour == hour }) {
            buckets[i].points += points
        } else {
            buckets.append(UsageBucket(account: account, serviceID: serviceID, hour: hour, points: points))
        }
    }

    /// 戻り時刻の、取得元ごとの小さな揺れ（/usage は分単位など）は、同じ期間とみなす。
    static let jitter: TimeInterval = 10 * 60

    /// 取得できた数字を、記録に足す。変化があったら true。
    @discardableResult
    public mutating func observe(account: UUID, serviceID: String, snapshot: Snapshot, now: Date) -> Bool {
        var changed = false
        for w in snapshot.windows {
            guard let reset = w.resetsAt, let used = w.usedPercent else { continue }
            let key = "\(account.uuidString)|\(w.label)"
            if var cur = open[key], abs(cur.resetsAt.timeIntervalSince(reset)) <= Self.jitter {
                if used > cur.peakUsed {
                    // 増えた分を、増えたことに気づいた時刻に足す（最初に見た値は、いつ使ったか分からないので足さない）。
                    if Self.isBudgetWindow(w.label) {
                        addBucket(account: account, serviceID: serviceID, at: snapshot.fetchedAt, points: used - cur.peakUsed)
                    }
                    cur.peakUsed = used
                    changed = true
                }
                cur.lastSeen = max(cur.lastSeen, snapshot.fetchedAt)
                if w.isExhausted && !cur.hitLimit {
                    cur.hitLimit = true
                    limits.append(LimitEvent(account: account, serviceID: serviceID, label: w.label,
                                             start: min(now, snapshot.fetchedAt), until: reset))
                    changed = true
                }
                open[key] = cur
            } else {
                // 古い記録が、後から届いたときは無視する。
                if let prev = open[key], prev.resetsAt > reset { continue }
                // 新しい期間。前の期間を締める。
                if let prev = open[key] { periods.append(prev) }
                let hit = w.isExhausted
                open[key] = WindowPeriod(account: account, serviceID: serviceID, label: w.label, resetsAt: reset,
                                         peakUsed: used, firstSeen: snapshot.fetchedAt, lastSeen: snapshot.fetchedAt,
                                         hitLimit: hit)
                if hit {
                    limits.append(LimitEvent(account: account, serviceID: serviceID, label: w.label,
                                             start: min(now, snapshot.fetchedAt), until: reset))
                }
                changed = true
            }
        }
        return changed
    }

    /// 戻り時刻を過ぎた期間を締める（使われなくなった枠を、いつまでも開けておかない）。
    /// 古い時間ごとの記録（120日より前）は、捨てる。
    public mutating func closeFinished(now: Date) {
        buckets.removeAll { $0.hour < now.addingTimeInterval(-120 * 86400) }
        for (key, p) in open where p.resetsAt < now.addingTimeInterval(-Self.jitter) {
            periods.append(p)
            open.removeValue(forKey: key)
        }
    }

    /// アカウントを消したら、その記録も消す。
    public mutating func forget(account: UUID) {
        periods.removeAll { $0.account == account }
        limits.removeAll { $0.account == account }
        buckets.removeAll { $0.account == account }
        open = open.filter { $0.value.account != account }
    }
}

// MARK: - 集計

public struct ServiceSummary: Equatable, Sendable {
    public var account: UUID
    public var serviceID: String
    /// 制限に当たった回数。
    public var limitHits: Int
    /// 制限で待たされた時間（秒）。
    public var waited: TimeInterval
    /// 週の枠の、使い切り率（リセットまで見えた期間の平均）。分からなければ nil。
    public var weeklyUse: Double?
    /// 週の枠を、リセットまでに捨てた%の平均。
    public var weeklyUnused: Double?
}

public struct RangeSummary: Equatable, Sendable {
    public var from: Date
    public var to: Date
    public var services: [ServiceSummary]
    public var limitHits: Int { services.reduce(0) { $0 + $1.limitHits } }
    public var waited: TimeInterval { services.reduce(0) { $0 + $1.waited } }
}

public enum ReviewSpan: String, CaseIterable, Sendable {
    case day, week, month
    public var label: String {
        switch self { case .day: return "日"; case .week: return "週"; case .month: return "月" }
    }
}

extension UsageHistory {
    /// `date` を含む、日・週・月の範囲（この Mac のタイムゾーン、週は月曜はじまり）。
    public static func range(_ span: ReviewSpan, containing date: Date, calendar: Calendar = .current) -> (Date, Date) {
        var cal = calendar
        cal.firstWeekday = 2
        let comp: Calendar.Component = span == .day ? .day : span == .week ? .weekOfYear : .month
        let interval = cal.dateInterval(of: comp, for: date)!
        return (interval.start, interval.end)
    }

    public func summary(from: Date, to: Date, now: Date) -> RangeSummary {
        var keys: [String: (UUID, String)] = [:]
        for l in limits { keys["\(l.account)|\(l.serviceID)"] = (l.account, l.serviceID) }
        let allPeriods = periods + Array(open.values)
        for p in allPeriods { keys["\(p.account)|\(p.serviceID)"] = (p.account, p.serviceID) }

        let services = keys.values.map { (account, serviceID) -> ServiceSummary in
            let ls = limits.filter { $0.account == account && $0.serviceID == serviceID }
            let hits = ls.filter { $0.start >= from && $0.start < to }.count
            let waited = ls.reduce(0.0) { sum, l in
                let s = max(l.start, from), e = min(l.until, to, now)
                return sum + max(0, e.timeIntervalSince(s))
            }
            let weekly = periods.filter {
                $0.account == account && $0.serviceID == serviceID && $0.label == "週の枠"
                    && $0.resetsAt >= from && $0.resetsAt < to && $0.observedToEnd
            }
            let use = weekly.isEmpty ? nil : weekly.map(\.peakUsed).reduce(0, +) / Double(weekly.count)
            let unused = weekly.isEmpty ? nil : weekly.compactMap(\.unused).reduce(0, +) / Double(weekly.count)
            return ServiceSummary(account: account, serviceID: serviceID, limitHits: hits, waited: waited,
                                  weeklyUse: use, weeklyUnused: unused)
        }
        .sorted { $0.serviceID < $1.serviceID }
        return RangeSummary(from: from, to: to, services: services)
    }
}

// MARK: - 提案（記録から言えることだけ）

public struct Suggestion: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case planDown, frequentLimits, shiftReset, useItOrLoseIt }
    public var kind: Kind
    public var account: UUID
    public var text: String
    public var id: String { "\(kind.rawValue)|\(account)" }
}

extension UsageHistory {
    /// 名前は、表示用に外から渡す（記録はサービスIDしか持たない）。
    public func suggestions(now: Date, name: (UUID) -> String, calendar: Calendar = .current) -> [Suggestion] {
        var out: [Suggestion] = []
        let accounts = Set(periods.map(\.account) + open.values.map(\.account) + limits.map(\.account))

        for a in accounts.sorted(by: { $0.uuidString < $1.uuidString }) {
            let n = name(a)

            // 1. 週の枠を、3週続けて半分も使っていない（制限にも当たっていない）
            let weeks = periods.filter { $0.account == a && $0.label == "週の枠" && $0.observedToEnd }
                .sorted { $0.resetsAt < $1.resetsAt }.suffix(3)
            if weeks.count == 3, weeks.allSatisfy({ $0.peakUsed < 50 && !$0.hitLimit }) {
                let avg = Int((weeks.map(\.peakUsed).reduce(0, +) / 3).rounded())
                out.append(Suggestion(kind: .planDown, account: a,
                    text: "\(n): 週の枠を、3週続けて半分も使っていません（平均\(avg)%）。下のプランで足りる可能性があります。"))
            }

            // 2. 直近2週間で、制限に何度も当たっている
            let recent = limits.filter { $0.account == a && $0.start >= now.addingTimeInterval(-14 * 86400) }
            if recent.count >= 6 {
                let hours = recent.reduce(0.0) { $0 + max(0, min($1.until, now).timeIntervalSince($1.start)) } / 3600
                out.append(Suggestion(kind: .frequentLimits, account: a,
                    text: "\(n): 直近2週間で\(recent.count)回、制限に当たり、合計\(Int(hours.rounded()))時間待っています。上のプランか、他のツールとの併用を検討する価値があります。"))
            }

            // 3. 5時間枠の制限が、午後に集中している（始めた時刻で、リセットの時刻が決まる）
            let fiveHour = limits.filter { $0.account == a && $0.label == "5時間枠" }
            if fiveHour.count >= 3 {
                let afternoon = fiveHour.filter { (12..<18).contains(calendar.component(.hour, from: $0.start)) }.count
                if Double(afternoon) / Double(fiveHour.count) >= 0.6 {
                    out.append(Suggestion(kind: .shiftReset, account: a,
                        text: "\(n): 5時間枠の制限は、午後に多く当たっています。5時間枠は、最初に使った時刻から数えるので、朝のうちに一度使い始めておくと、午後の早い時間にリセットされます。"))
                }
            }

            // 4. 週の枠が、たくさん残ったまま、もうすぐリセット
            if let cur = open.values.first(where: { $0.account == a && $0.label == "週の枠" }),
               cur.resetsAt > now, cur.resetsAt.timeIntervalSince(now) <= 24 * 3600, cur.peakUsed <= 60 {
                out.append(Suggestion(kind: .useItOrLoseIt, account: a,
                    text: "\(n): 週の枠が、あと\(Int((100 - cur.peakUsed).rounded()))%残っています。\(formatRemaining(until: cur.resetsAt, now: now))でリセットされます。"))
            }
        }
        return out
    }
}

// MARK: - 棒グラフ用の集計

public struct UsageBar: Identifiable, Equatable, Sendable {
    public var start: Date
    public var account: UUID
    public var serviceID: String
    public var points: Double
    public var id: String { "\(account)|\(start.timeIntervalSince1970)" }
}

public struct LimitMark: Identifiable, Equatable, Sendable {
    public var start: Date
    public var until: Date
    public var account: UUID
    public var serviceID: String
    public var label: String
    public var id: String { "\(account)|\(label)|\(start.timeIntervalSince1970)" }
}

extension UsageHistory {
    /// 日の表示は1時間ごと、週・月の表示は1日ごとに集める。アカウントごとに分ける。
    public func usageBars(span: ReviewSpan, from: Date, to: Date, calendar: Calendar = .current) -> [UsageBar] {
        var sums: [String: UsageBar] = [:]
        for b in buckets where b.hour >= from && b.hour < to {
            let start = span == .day ? b.hour : calendar.startOfDay(for: b.hour)
            let key = "\(b.account)|\(start.timeIntervalSince1970)"
            if var cur = sums[key] {
                cur.points += b.points
                sums[key] = cur
            } else {
                sums[key] = UsageBar(start: start, account: b.account, serviceID: b.serviceID, points: b.points)
            }
        }
        return sums.values.sorted { ($0.start, $0.account.uuidString) < ($1.start, $1.account.uuidString) }
    }

    /// 制限に当たった時刻（範囲の中）。
    public func limitMarks(from: Date, to: Date) -> [LimitMark] {
        limits.filter { $0.start >= from && $0.start < to }
            .map { LimitMark(start: $0.start, until: $0.until, account: $0.account, serviceID: $0.serviceID, label: $0.label) }
            .sorted { $0.start < $1.start }
    }

    /// 時間帯（0〜23時）ごとの使用量の合計。範囲の中の、何時によく使うか。
    public func hourOfDayTotals(from: Date, to: Date, calendar: Calendar = .current) -> [Double] {
        var totals = [Double](repeating: 0, count: 24)
        for b in buckets where b.hour >= from && b.hour < to {
            totals[calendar.component(.hour, from: b.hour)] += b.points
        }
        return totals
    }
}
