import Foundation
import EventKit
import CooltimeCore

/// 制限が解ける時刻に、iPhone のリマインダーの「Cooltime」リストへ、項目を置く（iCloud で iPhone に届く）。
/// iPhone 自身が、その時刻に通知を鳴らす（Mac が寝ていても届く）。ウィジェットでは、リストに「Cooltime」を選ぶ。
/// 置くのは、サービス名と時刻だけ。外のサービスは使わない。
@MainActor
enum RemindersSync {
    static let enabledKey = "remindersEnabled"
    static let listTitle = "Cooltime"
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    private static let store = EKEventStore()
    private static let notePrefix = "cooltime:"
    private static var running = false

    static var authorized: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }

    /// 初めてのときだけ、macOS が許可を聞く。
    static func requestAccess() async -> Bool {
        if authorized { return true }
        return (try? await store.requestFullAccessToReminders()) ?? false
    }

    private static func list() throws -> EKCalendar {
        if let c = store.calendars(for: .reminder).first(where: { $0.title == listTitle }) { return c }
        let c = EKCalendar(for: .reminder, eventStore: store)
        c.title = listTitle
        guard let source = store.defaultCalendarForNewReminders()?.source
                ?? store.sources.first(where: { $0.sourceType == .calDAV }) else {
            throw NSError(domain: "Cooltime", code: 1, userInfo: [NSLocalizedDescriptionKey: "リマインダーの保存先（iCloud）が見つかりません"])
        }
        c.source = source
        try store.saveCalendar(c, commit: true)
        return c
    }

    private static func existing(in cal: EKCalendar) async -> [ExistingReminder] {
        await withCheckedContinuation { cont in
            store.fetchReminders(matching: store.predicateForReminders(in: [cal])) { reminders in
                let list: [ExistingReminder] = (reminders ?? []).compactMap { r in
                    guard let note = r.notes, note.hasPrefix(notePrefix) else { return nil }  // 自分が置いたものだけ
                    let due = r.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
                    return ExistingReminder(id: r.calendarItemIdentifier, key: String(note.dropFirst(notePrefix.count)),
                                            due: due, completed: r.isCompleted)
                }
                cont.resume(returning: list)
            }
        }
    }

    private static func setDue(_ r: EKReminder, _ due: Date) {
        r.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: due)
        for a in r.alarms ?? [] { r.removeAlarm(a) }
        r.addAlarm(EKAlarm(absoluteDate: due))
    }

    /// 戻る時刻を、リマインダーに合わせる。失敗したときは、理由を返す。
    @discardableResult
    static func sync(_ entries: [StatusEntry], now: Date) async -> String? {
        guard authorized else { return "リマインダーへのアクセスが許可されていません。システム設定 → プライバシーとセキュリティ → リマインダー で、Cooltime を許可してください。" }
        guard !running else { return nil }
        running = true
        defer { running = false }
        do {
            let cal = try list()
            let actions = planReminders(desired: desiredReminders(from: entries), existing: await existing(in: cal), now: now)
            for a in actions {
                switch a {
                case .create(let d):
                    let r = EKReminder(eventStore: store)
                    r.calendar = cal
                    r.title = d.title
                    r.notes = notePrefix + d.key
                    setDue(r, d.due)
                    try store.save(r, commit: false)
                case .update(let id, let due, let title):
                    if let r = store.calendarItem(withIdentifier: id) as? EKReminder {
                        r.title = title
                        setDue(r, due)
                        try store.save(r, commit: false)
                    }
                case .delete(let id):
                    if let r = store.calendarItem(withIdentifier: id) as? EKReminder { try store.remove(r, commit: false) }
                }
            }
            if !actions.isEmpty { try store.commit() }
            return nil
        } catch {
            return "リマインダーに書けませんでした: \(error.localizedDescription)"
        }
    }
}
