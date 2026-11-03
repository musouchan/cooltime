import Foundation

/// メニューバーに出すもの。キャラクターと、一番大事な1つの数字。
/// `source` は、その数字のもとになったサービスの ID（アプリのアイコンを添えるため）。
public enum MenuBarDisplay: Equatable, Sendable {
    /// 制限中。一番早く戻るものの時刻。
    case limited(until: Date, source: String)
    /// 制限なし。残りが最も少ないもの（%）。
    case remaining(percent: Int, source: String)
    /// 制限なし、かつ割合で出せるものが無いとき。残高が最も少ないもの。
    case credit(text: String, source: String)
    /// どのサービスからも、数字が取れていない。キャラクターだけ。
    case failed

    public var characterState: CharacterState {
        switch self {
        case .limited: return .limit
        case .remaining, .credit: return .ok
        case .failed: return .fail
        }
    }

    public var source: String? {
        switch self {
        case .limited(_, let s), .remaining(_, let s), .credit(_, let s): return s
        case .failed: return nil
        }
    }

    public func text(now: Date) -> String? {
        switch self {
        case .limited(let until, _): return formatRemainingShort(until: until, now: now)
        case .remaining(let p, _): return "残り\(p)%"
        case .credit(let t, _): return t
        case .failed: return nil
        }
    }
}

/// メニューバー用の、短い時間の表示。1日以上は、日だけ（「あと2日」）。
public func formatRemainingShort(until: Date, now: Date) -> String {
    let minutes = max(1, Int((until.timeIntervalSince(now) / 60).rounded(.up)))
    if minutes >= 24 * 60 { return "あと\(minutes / (24 * 60))日" }
    return formatRemaining(until: until, now: now)
}

public struct MenuBarCandidate: Sendable {
    public var state: QuotaState
    public var snapshot: Snapshot?
    /// 最新の取得に失敗している（数字は古い）。
    public var fetchFailed: Bool
    /// サービスの ID。
    public var source: String

    public init(state: QuotaState, snapshot: Snapshot?, fetchFailed: Bool, source: String = "") {
        self.state = state
        self.snapshot = snapshot
        self.fetchFailed = fetchFailed
        self.source = source
    }
}

/// 上から順に、当てはまったものを出す。
///  1. 制限中があれば、一番早く戻るものの時間
///  2. 制限なしなら、残りが最も少ないもの（割合。無ければ、残高が最も少ないもの）
///  3. 数字が1つも取れていなければ、キャラクターだけ
/// 取得に失敗している・目安を過ぎた・未取得のものの数字は、使わない（古い数字を出さない）。
public func makeMenuBarDisplay(_ items: [MenuBarCandidate]) -> MenuBarDisplay {
    let limited = items.compactMap { item -> (Date, String)? in
        if case .limited(let until) = item.state { return (until, item.source) }
        return nil
    }
    if let first = limited.min(by: { $0.0 < $1.0 }) { return .limited(until: first.0, source: first.1) }

    let usable = items.filter { !$0.fetchFailed && $0.state == .available && $0.snapshot != nil }
    let percents = usable.compactMap { item -> (Double, String)? in
        guard let p = item.snapshot?.windows.filter({ !$0.isExhausted }).compactMap(\.remainingPercent).min() else { return nil }
        return (p, item.source)
    }
    if let lowest = percents.min(by: { $0.0 < $1.0 }) { return .remaining(percent: Int(lowest.0.rounded()), source: lowest.1) }

    let credits = usable.compactMap { item -> (CreditBalance, String)? in
        item.snapshot?.credit.map { ($0, item.source) }
    }
    if let lowest = credits.min(by: { $0.0.amount < $1.0.amount }) { return .credit(text: formatMoney(lowest.0), source: lowest.1) }
    return .failed
}
