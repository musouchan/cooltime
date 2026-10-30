import Foundation

/// 1つの利用枠（5時間枠・週の枠・月の枠など）。
public struct UsageWindow: Codable, Equatable, Sendable {
    public var label: String
    /// 使った割合 0...100。取れないときは nil。
    public var usedPercent: Double?
    /// 残りの数（クレジット数・文字数など）。割合でなく数で見せたいもの。
    public var remainingCount: Double?
    /// 公式の応答にある戻り時刻。無ければ nil（推定はしない）。
    public var resetsAt: Date?

    public init(label: String, usedPercent: Double? = nil, remainingCount: Double? = nil, resetsAt: Date? = nil) {
        self.label = label
        self.usedPercent = usedPercent
        self.remainingCount = remainingCount
        self.resetsAt = resetsAt
    }

    public var remainingPercent: Double? { usedPercent.map { max(0, 100 - $0) } }

    public var isExhausted: Bool {
        if let used = usedPercent, used >= 100 { return true }
        if let left = remainingCount, left <= 0 { return true }
        return false
    }
}

/// 時間では戻らない残高。
public struct CreditBalance: Codable, Equatable, Sendable {
    public var amount: Double
    /// "USD" / "CNY" など。通貨でないものは "credits"。
    public var currency: String
    /// 予算のリセットがあるものだけ。
    public var resetsAt: Date?
    public var note: String?

    public init(amount: Double, currency: String, resetsAt: Date? = nil, note: String? = nil) {
        self.amount = amount
        self.currency = currency
        self.resetsAt = resetsAt
        self.note = note
    }
}

/// ある時点で取得した結果。
public struct Snapshot: Codable, Equatable, Sendable {
    public var windows: [UsageWindow]
    public var credit: CreditBalance?
    public var fetchedAt: Date

    public init(windows: [UsageWindow] = [], credit: CreditBalance? = nil, fetchedAt: Date) {
        self.windows = windows
        self.credit = credit
        self.fetchedAt = fetchedAt
    }
}

public enum AccountType: String, Codable, CaseIterable, Sendable {
    case personal, business
    public var label: String { self == .personal ? "個人" : "法人" }
}

/// ユーザーが追加した1アカウント。秘密（APIキー）は持たない（Keychain に別保存）。
public struct Account: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var serviceID: String
    public var name: String
    public var type: AccountType
    /// 支払いページ。空ならサービスの既定を使う。
    public var paymentURL: String
    /// Claude Code のステータスライン取得元の識別名（複数アカウント用）。
    public var slot: String

    public init(id: UUID = UUID(), serviceID: String, name: String = "", type: AccountType = .personal,
                paymentURL: String = "", slot: String = "default") {
        self.id = id
        self.serviceID = serviceID
        self.name = name
        self.type = type
        self.paymentURL = paymentURL
        self.slot = slot
    }
}
