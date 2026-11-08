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
    let future = exhausted.compactMap { $0.resetsAt }.filter { $0 > now }
    if let until = future.max() { return .limited(until: until) }
    if !exhausted.isEmpty {
        return .stale(since: exhausted.compactMap { $0.resetsAt }.max() ?? snapshot.fetchedAt)
    }
    // 取得した後に戻り時刻を過ぎた枠の数字は、もう当てにならない。「戻った」とも決めず、再取得を促す。
    let outdated = snapshot.windows.compactMap { w -> Date? in
        guard let r = w.resetsAt, r <= now, snapshot.fetchedAt < r else { return nil }
        return r
    }
    if let since = outdated.max() { return .stale(since: since) }
    return .available
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

/// 枠の名前を、短くする（「5時間枠」→「5時間」、「週の枠」→「週」、「月の利用額」→「月」）。
public func shortWindowLabel(_ label: String) -> String {
    if label.contains("時間") || label.contains("分") {
        // 「5時間枠」→「5時間」
        return label.replacingOccurrences(of: "枠", with: "")
    }
    if label.contains("週") { return "週" }
    if label.contains("月") { return "月" }
    return label.replacingOccurrences(of: "の枠", with: "").replacingOccurrences(of: "枠", with: "")
}

/// 管理画面の一覧用。何の残りかが分かるように、枠の名前を付ける（「週 残り28%」）。
/// 数がある枠はその数、無ければ、残りが最も少ない枠の割合。
public func availableSummaryLabeled(_ snapshot: Snapshot) -> String? {
    let candidates = snapshot.windows.filter { !$0.isExhausted }
    if let w = candidates.first(where: { $0.remainingCount != nil }), let n = w.remainingCount {
        return "\(shortWindowLabel(w.label)) 残り\(Int(n.rounded()))"
    }
    let withPercent = candidates.compactMap { w in w.remainingPercent.map { (w, $0) } }
    if let (w, p) = withPercent.min(by: { $0.1 < $1.1 }) {
        return "\(shortWindowLabel(w.label)) 残り\(Int(p.rounded()))%"
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
