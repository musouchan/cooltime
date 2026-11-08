import Foundation

/// 「戻った」ことの種類。
public enum Recovery: Equatable, Sendable {
    /// 制限中だったものが、使えるようになった（取り直した結果が「使用可能」）。
    case limitEnded
    /// クレジット残高が増えた（チャージや月のリセット）。
    case creditIncreased(from: Double, to: Double, currency: String)
}

/// 取り直した結果から、「戻った」かを決める。
/// - wasLimited: 前に「制限中」と分かっていたか（アプリを閉じていた間のぶんも、覚えておく）。
/// 取り直す前に戻り時刻を過ぎただけ（stale）では、戻ったとは決めない。
public func detectRecovery(wasLimited: Bool, previous: Snapshot?, current: Snapshot, now: Date) -> Recovery? {
    if wasLimited, evaluate(current, now: now) == .available { return .limitEnded }
    if let p = previous?.credit, let c = current.credit, p.currency == c.currency, c.amount > p.amount + 0.0001 {
        return .creditIncreased(from: p.amount, to: c.amount, currency: c.currency)
    }
    return nil
}

public func recoveryMessage(serviceName: String, recovery: Recovery) -> String {
    switch recovery {
    case .limitEnded:
        return "\(serviceName) が使えるようになりました"
    case .creditIncreased(let from, let to, let currency):
        return "\(serviceName) のクレジットが増えました（\(formatMoney(CreditBalance(amount: from, currency: currency))) → \(formatMoney(CreditBalance(amount: to, currency: currency)))）"
    }
}
