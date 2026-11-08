import Foundation

/// iPhone のリマインダー（「Cooltime」リスト）に置きたい項目。1アカウントにつき1つ。
public struct DesiredReminder: Equatable, Sendable {
    public var key: String
    public var title: String
    public var due: Date
    public init(key: String, title: String, due: Date) {
        self.key = key
        self.title = title
        self.due = due
    }
}

/// いま「Cooltime」リストにある項目。
public struct ExistingReminder: Equatable, Sendable {
    public var id: String
    public var key: String
    public var due: Date?
    public var completed: Bool
    public init(id: String, key: String, due: Date?, completed: Bool) {
        self.id = id
        self.key = key
        self.due = due
        self.completed = completed
    }
}

public enum ReminderAction: Equatable, Sendable {
    case create(DesiredReminder)
    case update(id: String, due: Date, title: String)
    case delete(id: String)
}

/// 制限中のものについて、戻る時刻にリマインダーを置く。
/// - 同じアカウントの、未完了の項目は、1つだけ使い回す（期限を過ぎて残っているものも、次の制限で使い回すので、増えない）。
/// - 戻る時刻が2分以上ずれたら、期限を直す。
/// - 制限でなくなったのに、まだ期限が来ていない項目は、鳴らないよう消す。期限を過ぎたものは「使える」の印として残す。
/// - 完了済みの項目には、触らない。
public func planReminders(desired: [DesiredReminder], existing: [ExistingReminder], now: Date) -> [ReminderAction] {
    var actions: [ReminderAction] = []
    let open = existing.filter { !$0.completed }
    for d in desired {
        let mine = open.filter { $0.key == d.key }
        if let keep = mine.first {
            if keep.due == nil || abs(keep.due!.timeIntervalSince(d.due)) > 120 {
                actions.append(.update(id: keep.id, due: d.due, title: d.title))
            }
            for extra in mine.dropFirst() { actions.append(.delete(id: extra.id)) }
        } else {
            actions.append(.create(d))
        }
    }
    let wanted = Set(desired.map(\.key))
    for e in open where !wanted.contains(e.key) {
        if let due = e.due, due > now { actions.append(.delete(id: e.id)) }
    }
    return actions
}

/// 制限中のものだけを、置きたい項目にする。
public func desiredReminders(from entries: [StatusEntry]) -> [DesiredReminder] {
    entries.compactMap { e in
        guard !e.key.isEmpty, case .limited(let until) = e.state else { return nil }
        return DesiredReminder(key: e.key, title: "\(e.title) が使えるようになりました", due: until)
    }
}
