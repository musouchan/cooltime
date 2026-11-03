import Foundation

/// メニューバーに出すもの。キャラクターと、一番大事な1つの数字。
/// `source` は、その数字のもとになったサービスの ID（アプリのアイコンを添えるため）。
public enum MenuBarDisplay: Equatable, Sendable {
    /// 制限中。一番早く戻るものの時刻。
    case limited(until: Date, source: String)
    /// 制限なし。5時間枠など、短い枠の残り（%）。週・月の枠は、残りが10%を切ったときだけ（`scope` に「週」「月」）。
    case remaining(percent: Int, source: String, scope: String?)
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
        case .limited(_, let s), .remaining(_, let s, _), .credit(_, let s): return s
        case .failed: return nil
        }
    }

    public func text(now: Date) -> String? {
        switch self {
        case .limited(let until, _): return formatRemainingShort(until: until, now: now)
        case .remaining(let p, _, let scope): return "\(scope ?? "")残り\(p)%"
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
///  2. 制限なしなら、5時間枠など短い枠の、残りが最も少ないもの（「残り87%」）。
///     週・月の枠は、残りが10%を切ったときだけ、それを優先して出す（「週残り9%」）。
///     短い枠が1つも無いときは、週・月の枠の残りが最も少ないもの。割合が無ければ、残高が最も少ないもの
///  3. 数字が1つも取れていなければ、キャラクターだけ
/// 取得に失敗している・目安を過ぎた・未取得のものの数字は、使わない（古い数字を出さない）。
public func makeMenuBarDisplay(_ items: [MenuBarCandidate]) -> MenuBarDisplay {
    let limited = items.compactMap { item -> (Date, String)? in
        if case .limited(let until) = item.state { return (until, item.source) }
        return nil
    }
    if let first = limited.min(by: { $0.0 < $1.0 }) { return .limited(until: first.0, source: first.1) }

    let usable = items.filter { !$0.fetchFailed && $0.state == .available && $0.snapshot != nil }
    struct Pick { var percent: Int; var source: String; var scope: String? }
    var short: [Pick] = [], budget: [Pick] = []
    for item in usable {
        for w in item.snapshot?.windows ?? [] where !w.isExhausted {
            guard let p = w.remainingPercent else { continue }
            if UsageHistory.isBudgetWindow(w.label) {
                let scope = w.label.contains("週") ? "週" : w.label.contains("月") ? "月" : nil
                budget.append(Pick(percent: Int(p.rounded()), source: item.source, scope: scope))
            } else {
                short.append(Pick(percent: Int(p.rounded()), source: item.source, scope: nil))
            }
        }
    }
    // 週・月の枠は、残りが10%を切ったときだけ、5時間枠より優先して出す
    if let low = budget.filter({ $0.percent < 10 && $0.scope != nil }).min(by: { $0.percent < $1.percent }) {
        return .remaining(percent: low.percent, source: low.source, scope: low.scope)
    }
    if let s = short.min(by: { $0.percent < $1.percent }) { return .remaining(percent: s.percent, source: s.source, scope: nil) }
    if let b = budget.min(by: { $0.percent < $1.percent }) { return .remaining(percent: b.percent, source: b.source, scope: nil) }

    let credits = usable.compactMap { item -> (CreditBalance, String)? in
        item.snapshot?.credit.map { ($0, item.source) }
    }
    if let lowest = credits.min(by: { $0.0.amount < $1.0.amount }) { return .credit(text: formatMoney(lowest.0), source: lowest.1) }
    return .failed
}
