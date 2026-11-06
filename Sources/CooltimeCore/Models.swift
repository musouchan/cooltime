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
    /// 公式に報告された実績値（残量や上限とは別）。例: 請求期間のコスト。
    public var reportedAmount: Double?
    public var reportedUnit: String?
    /// 公式APIが明示した利用停止。数値の残量とは別に保持する。
    public var isLimited: Bool?

    public init(label: String, usedPercent: Double? = nil, remainingCount: Double? = nil,
                resetsAt: Date? = nil, reportedAmount: Double? = nil, reportedUnit: String? = nil, isLimited: Bool? = nil) {
        self.label = label
        self.usedPercent = usedPercent
        self.remainingCount = remainingCount
        self.resetsAt = resetsAt
        self.reportedAmount = reportedAmount
        self.reportedUnit = reportedUnit
        self.isLimited = isLimited
    }

    public var remainingPercent: Double? { usedPercent.map { max(0, 100 - $0) } }

    public var isExhausted: Bool {
        if isLimited == true { return true }
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
    /// 月額（円）。本人が入力する（上書き）。振り返りで、払っている額と使い方を並べるために使う。
    public var monthlyPrice: Int?
    /// プラン（`PlanCatalog` の ID。例: "plus"）。Codex は自動、Claude は本人が選ぶ。
    public var planID: String?

    public init(id: UUID = UUID(), serviceID: String, name: String = "", type: AccountType = .personal,
                paymentURL: String = "", slot: String = "default", monthlyPrice: Int? = nil, planID: String? = nil) {
        self.id = id
        self.serviceID = serviceID
        self.name = name
        self.type = type
        self.paymentURL = paymentURL
        self.slot = slot
        self.monthlyPrice = monthlyPrice
        self.planID = planID
    }
}

