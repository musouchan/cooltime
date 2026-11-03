import SwiftUI
import Charts
import CooltimeCore

/// 振り返り: 日・週・月ごとに、制限に当たった回数、待たされた時間、週の枠の使い切り率を見る。
/// 記録から言えることだけを、提案として出す。
struct ReviewView: View {
    @EnvironmentObject var model: AppModel
    @State private var span: ReviewSpan = .week
    @State private var anchor = Date()
    @AppStorage(DisplayStyle.key) private var displayStyle = DisplayStyle.simple.rawValue

    private var ghost: Bool { displayStyle == DisplayStyle.ghost.rawValue }

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

                chartSection(from: from, to: to)

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

    // MARK: シンプルな棒グラフ

    private var xStride: (Calendar.Component, Int) {
        switch span {
        case .day: return (.hour, 3)
        case .week: return (.day, 1)
        case .month: return (.day, 5)
        }
    }

    private var xFormat: Date.FormatStyle {
        switch span {
        case .day: return .dateTime.hour()
        case .week: return .dateTime.weekday(.abbreviated)
        case .month: return .dateTime.day()
        }
    }

    private func simpleChart(from: Date, to: Date, bars: [UsageBar], marks: [LimitMark]) -> some View {
        Chart {
            ForEach(bars) { b in
                BarMark(x: .value("日時", b.start, unit: span == .day ? .hour : .day), y: .value("使った量", b.points))
                    .foregroundStyle(by: .value("サービス", model.displayName(b.account)))
            }
            ForEach(marks) { m in
                RuleMark(x: .value("上限", m.start))
                    .foregroundStyle(.red)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .annotation(position: .top, alignment: .center, spacing: 2) {
                        Label("上限", systemImage: "pause.circle.fill").font(.caption2).foregroundStyle(.red)
                    }
            }
        }
        .chartXScale(domain: from...to)
        .chartXAxis {
            AxisMarks(values: .stride(by: xStride.0, count: xStride.1)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: xFormat)
            }
        }
        .chartYAxisLabel("週（月）の枠を使った量（%）")
        .frame(height: 210)
    }

    private func simpleHourChart(totals: [Double]) -> some View {
        Chart {
            ForEach(0..<24, id: \.self) { h in
                BarMark(x: .value("時", h), y: .value("使った量", totals[h]))
            }
        }
        .chartXAxis {
            AxisMarks(values: [0, 3, 6, 9, 12, 15, 18, 21]) { value in
                AxisGridLine()
                AxisValueLabel { if let h = value.as(Int.self) { Text("\(h)時") } }
            }
        }
        .frame(height: 110)
    }

    // MARK: おばけ積み

    /// 1匹が何%分か。積み上がる数が、10匹までに収まるように決める。
    private func unit(for maxValue: Double) -> Double {
        [1, 2, 5, 10, 20, 25, 50, 100].first { ceil(maxValue / $0) <= 10 } ?? 100
    }

    private func columns(from: Date, to: Date, bars: [UsageBar], marks: [LimitMark]) -> [GhostStackChart.Column] {
        let cal = Calendar.current
        let comp: Calendar.Component = span == .day ? .hour : .day
        var totals: [Int: Double] = [:]
        for b in bars { totals[Int(b.start.timeIntervalSince1970), default: 0] += b.points }

        var out: [GhostStackChart.Column] = []
        var start = from
        var index = 0
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "E"
        while start < to, index < 400 {
            let next = cal.date(byAdding: comp, value: 1, to: start) ?? to
            let label: String?
            switch span {
            case .day: label = cal.component(.hour, from: start) % 3 == 0 ? "\(cal.component(.hour, from: start))" : nil
            case .week: label = f.string(from: start)
            case .month: label = (cal.component(.day, from: start) - 1) % 5 == 0 ? "\(cal.component(.day, from: start))" : nil
            }
            out.append(.init(id: index, label: label, value: totals[Int(start.timeIntervalSince1970)] ?? 0,
                             limit: marks.contains { $0.start >= start && $0.start < next }))
            start = next
            index += 1
        }
        return out
    }

    /// いつ使ったか（おばけ積み）と、上限に当たった日時、何時によく使うか。
    @ViewBuilder
    private func chartSection(from: Date, to: Date) -> some View {
        let bars = model.history.usageBars(span: span, from: from, to: to)
        let marks = model.history.limitMarks(from: from, to: to)
        let totals = model.history.hourOfDayTotals(from: from, to: to)
        let cols = columns(from: from, to: to, bars: bars, marks: marks)
        let unit = unit(for: cols.map(\.value).max() ?? 0)

        VStack(alignment: .leading, spacing: 10) {
            Text(span == .day ? "いつ使ったか（1時間ごと）" : "いつ使ったか（1日ごと）").font(.caption).foregroundStyle(.secondary)
            if bars.isEmpty && marks.isEmpty {
                Text("この期間は、使った記録がありません。").foregroundStyle(.secondary)
            } else {
                if ghost {
                    GhostStackChart(columns: cols, unit: unit, dayView: span == .day)
                        .frame(height: 230)
                    Label("おばけ1匹 ＝ 週（月）の枠の \(Int(unit))% 分。眠っている赤いおばけは、上限に当たった日", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    simpleChart(from: from, to: to, bars: bars, marks: marks)
                }

                if !marks.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(marks) { m in
                            Label("\(formatClock(m.start, now: model.now)) 上限に当たった（\(model.displayName(m.account)) \(m.label)。\(formatClock(m.until, now: model.now)) に戻る）",
                                  systemImage: "pause.circle")
                                .font(.caption)
                        }
                    }
                }
            }

            if span != .day, totals.contains(where: { $0 > 0 }) {
                Text("何時によく使うか（0〜23時の合計。大きいほど、よく使う）").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                if ghost {
                    GhostSizeRow(values: totals).frame(height: 96)
                } else {
                    simpleHourChart(totals: totals)
                }
            }

            if let peak = peakHour(span: span, bars: bars, totals: totals) {
                Label(peak, systemImage: "clock").font(.callout)
            }
            Text("週（月）の枠の使用%が増えた分を、増えたと気づいた時刻で集めています。1%ずつの記録なので、少しの量は、まとめて出ます。この機能を入れる前の分は、時間ごとには分かりません。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// 一番よく使った時間帯（日）／時間帯（週・月）の一言。
    private func peakHour(span: ReviewSpan, bars: [UsageBar], totals: [Double]) -> String? {
        let cal = Calendar.current
        if span == .day {
            var byHour: [Int: Double] = [:]
            for b in bars { byHour[cal.component(.hour, from: b.start), default: 0] += b.points }
            guard let top = byHour.max(by: { $0.value < $1.value }), top.value > 0 else { return nil }
            return "一番使った時間帯: \(top.key)〜\(top.key + 1)時（\(Int(top.value.rounded()))%分）"
        }
        guard let top = totals.enumerated().max(by: { $0.element < $1.element }), top.element > 0 else { return nil }
        return "一番よく使う時間帯: \(top.offset)〜\(top.offset + 1)時"
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
        guard let a = model.accounts.first(where: { $0.id == account }) else { return "—" }
        if let p = a.monthlyPrice { return "¥\(p.formatted())" }
        return PlanCatalog.option(serviceID: a.serviceID, id: a.planID).map { "$\($0.usdMonthly)" } ?? "—"
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
