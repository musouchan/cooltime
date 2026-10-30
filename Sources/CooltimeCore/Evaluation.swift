import Foundation

public enum QuotaState: Equatable, Sendable {
    /// 制限中。戻る時刻は公式の値。
    case limited(until: Date)
    /// 使用可能。
    case available
    /// 戻り目安を過ぎた。再取得するまで「使用可能」にはしない。
    case stale(since: Date)
    /// まだ取得していない。
    case unset
}

/// 取得結果と現在時刻から状態を決める。
/// 両方に残りが必要な複数の枠が尽きているときは、戻りが遅い方を使う。
public func evaluate(_ snapshot: Snapshot?, now: Date) -> QuotaState {
    guard let snapshot else { return .unset }
    let exhausted = snapshot.windows.filter { $0.isExhausted }
    if exhausted.isEmpty { return .available }
    let future = exhausted.compactMap { $0.resetsAt }.filter { $0 > now }
    if let until = future.max() { return .limited(until: until) }
    let since = exhausted.compactMap { $0.resetsAt }.max() ?? snapshot.fetchedAt
    return .stale(since: since)
}

/// 「使用可能」に出す残りの目安。数があれば数、無ければ割合。
public func availableSummary(_ snapshot: Snapshot) -> String? {
    let candidates = snapshot.windows.filter { !$0.isExhausted }
    if let w = candidates.first(where: { $0.remainingCount != nil }), let n = w.remainingCount {
        return "残り\(Int(n.rounded()))"
    }
    if let p = candidates.compactMap({ $0.remainingPercent }).min() {
        return "残り\(Int(p.rounded()))%"
    }
    return nil
}

public struct MenuBarPick: Equatable, Sendable {
    public let id: UUID
    public let until: Date
    /// 他にも制限中のものがある数（「+2」）。
    public let others: Int
}

/// メニューバーに出す「一番早く戻るもの」。制限中が無ければ nil（アプリのアイコンだけを出す）。
public func pickForMenuBar(_ entries: [(id: UUID, state: QuotaState)]) -> MenuBarPick? {
    let limited = entries.compactMap { e -> (UUID, Date)? in
        if case .limited(let until) = e.state { return (e.id, until) }
        return nil
    }.sorted { $0.1 < $1.1 }
    guard let first = limited.first else { return nil }
    return MenuBarPick(id: first.0, until: first.1, others: limited.count - 1)
}
