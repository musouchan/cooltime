import Foundation

/// テストで時刻を固定できるようにするための時計。
public protocol TimeSource: Sendable {
    var now: Date { get }
}

public struct SystemClock: TimeSource {
    public init() {}
    public var now: Date { Date() }
}

public struct FixedClock: TimeSource {
    public var now: Date
    public init(_ now: Date) { self.now = now }
}

public enum AccountKind: String, Codable, CaseIterable, Sendable {
    case personal, corporate
    public var label: String { self == .personal ? "個人" : "法人" }
}

/// 1つの利用枠（例: 5時間枠、週の枠、月の文字数）。
public struct WindowStatus: Equatable, Sendable {
    public let name: String
    /// 使った割合（0〜100）。
    public let usedPercent: Double
    /// 枠が戻る時刻。サービスが返した値だけを入れる。
    public let resetsAt: Date
    /// 「残り820」のような補足。
    public let detail: String?

    public init(name: String, usedPercent: Double, resetsAt: Date, detail: String? = nil) {
        self.name = name
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.detail = detail
    }
}

public struct CreditBalance: Equatable, Sendable {
    public let amount: Decimal
    public let currency: String
    public init(amount: Decimal, currency: String) {
        self.amount = amount
        self.currency = currency
    }

    public var text: String {
        let number = NSDecimalNumber(decimal: amount)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        let body = f.string(from: number) ?? "\(amount)"
        return currency == "USD" ? "$\(body)" : "\(body) \(currency)"
    }
}

/// 取得元から返ってきた結果。
public struct SourceResult: Equatable, Sendable {
    public var windows: [WindowStatus]
    public var credit: CreditBalance?
    public init(windows: [WindowStatus] = [], credit: CreditBalance? = nil) {
        self.windows = windows
        self.credit = credit
    }
}

public struct Snapshot: Equatable, Sendable {
    public let serviceID: String
    public let result: SourceResult
    public let fetchedAt: Date
    public init(serviceID: String, result: SourceResult, fetchedAt: Date) {
        self.serviceID = serviceID
        self.result = result
        self.fetchedAt = fetchedAt
    }
}

public enum DisplayState: Equatable, Sendable {
    /// 制限中。戻る時刻が分かっている。
    case limited(recoversAt: Date)
    /// 戻る目安の時刻を過ぎた。再取得するまで「戻った」とは決めない。
    case resetEstimatePassed(since: Date)
    case available(remainingPercent: Double)
    case credit(CreditBalance)
    case noData
}

extension Snapshot {
    /// 利用枠のうち1つでも使い切っていれば制限中。
    /// 複数の枠が切れているときは、全部戻るまで使えないので一番遅い時刻を採る。
    public func state(at now: Date) -> DisplayState {
        let windows = result.windows
        if windows.isEmpty {
            if let credit = result.credit { return .credit(credit) }
            return .noData
        }
        let exhausted = windows.filter { $0.usedPercent >= 100 }
        if exhausted.isEmpty {
            let used = windows.map(\.usedPercent).max() ?? 0
            return .available(remainingPercent: max(0, 100 - used))
        }
        let latest = exhausted.map(\.resetsAt).max()!
        return latest > now ? .limited(recoversAt: latest) : .resetEstimatePassed(since: latest)
    }
}
