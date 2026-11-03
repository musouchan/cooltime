import SwiftUI
import CooltimeCore

/// 振り返り: 日・週・月ごとに、制限に当たった回数、待たされた時間、週の枠の使い切り率を見る。
/// 記録から言えることだけを、提案として出す。
struct ReviewView: View {
    @EnvironmentObject var model: AppModel
    @State private var span: ReviewSpan = .week
    @State private var anchor = Date()

    var body: some View {
        let (from, to) = UsageHistory.range(span, containing: anchor)
        let summary = model.history.summary(from: from, to: to, now: model.now)
        let suggestions = model.history.suggestions(now: model.now, name: model.displayName)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Picker("期間", selection: $span) {
                        ForEach(ReviewSpan.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 180)
                    Spacer()
                    Button { anchor = shift(-1) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("前の期間")
                    Text(title(from, to)).monospacedDigit().frame(minWidth: 140)
                    Button { anchor = shift(1) } label: { Image(systemName: "chevron.right") }
                        .disabled(to > model.now).accessibilityLabel("次の期間")
                }

                HStack(spacing: 12) {
                    tile("制限に当たった回数", "\(summary.limitHits)回")
                    tile("制限で待った時間", formatDuration(summary.waited))
                    tile("週の枠の使い切り率", weeklyAverage(summary))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("サービスごと").font(.caption).foregroundStyle(.secondary)
                    if summary.services.isEmpty {
                        Text("この期間の記録はありません").foregroundStyle(.secondary)
                    } else {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                            GridRow {
                                Text("サービス"); Text("制限"); Text("待った時間"); Text("週の枠の使用"); Text("使い残し"); Text("月額")
                            }
                            .font(.caption).foregroundStyle(.secondary)
                            Divider().gridCellUnsizedAxes(.horizontal)
                            ForEach(summary.services, id: \.account) { s in
                                GridRow {
                                    Text(model.displayName(s.account)).lineLimit(1)
                                    Text("\(s.limitHits)回").monospacedDigit()
                                    Text(formatDuration(s.waited)).monospacedDigit()
                                    Text(s.weeklyUse.map { "\(Int($0.rounded()))%" } ?? "—").monospacedDigit()
                                    Text(s.weeklyUnused.map { "\(Int($0.rounded()))%" } ?? "—").monospacedDigit()
                                    Text(price(s.account)).monospacedDigit()
                                }
                            }
                        }
                    }
                    Text("週の枠の数字は、この期間にリセットされた週のうち、リセットの直前まで記録できた週だけで出します。記録できていない週は「—」です。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("提案").font(.caption).foregroundStyle(.secondary)
                    if suggestions.isEmpty {
                        Text("いまの記録からは、提案はありません。記録がたまると出ます（記録の開始: \(formatClock(model.history.startedAt, now: model.now))）。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(suggestions) { s in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: icon(s.kind)).frame(width: 18)
                                Text(s.text).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                Text("記録は、この Mac の中だけに保存します。会話の中身は記録しません（枠の%と時刻だけです）。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .frame(minWidth: 640, minHeight: 480)
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2).fontWeight(.semibold).monospacedDigit()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
    }

    private func weeklyAverage(_ s: RangeSummary) -> String {
        let uses = s.services.compactMap(\.weeklyUse)
        guard !uses.isEmpty else { return "—" }
        return "\(Int((uses.reduce(0, +) / Double(uses.count)).rounded()))%"
    }

    private func price(_ account: UUID) -> String {
        guard let p = model.accounts.first(where: { $0.id == account })?.monthlyPrice else { return "—" }
        return "¥\(p.formatted())"
    }

    private func icon(_ kind: Suggestion.Kind) -> String {
        switch kind {
        case .planDown: return "arrow.down.circle"
        case .frequentLimits: return "exclamationmark.circle"
        case .shiftReset: return "clock.arrow.circlepath"
        case .useItOrLoseIt: return "hourglass"
        }
    }

    private func shift(_ n: Int) -> Date {
        let comp: Calendar.Component = span == .day ? .day : span == .week ? .weekOfYear : .month
        return Calendar.current.date(byAdding: comp, value: n, to: anchor) ?? anchor
    }

    private func title(_ from: Date, _ to: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        switch span {
        case .day:
            f.dateFormat = "M月d日（E）"
            return f.string(from: from)
        case .week:
            f.dateFormat = "M/d"
            return "\(f.string(from: from))〜\(f.string(from: to.addingTimeInterval(-1)))"
        case .month:
            f.dateFormat = "yyyy年M月"
            return f.string(from: from)
        }
    }
}
