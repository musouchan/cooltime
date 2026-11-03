import SwiftUI
import AppKit
import CooltimeCore

struct PopoverView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.accounts.isEmpty {
                Text("サービスが未設定です。「管理…」から、使っているものを追加してください。")
                    .font(.callout).foregroundStyle(.secondary).padding(16)
            }
            if !model.limited.isEmpty || !model.stale.isEmpty {
                section("制限中") {
                    ForEach(model.limited) { LimitedRow(item: $0) }
                    ForEach(model.stale) { StaleRow(item: $0) }
                }
            }
            if !model.available.isEmpty {
                section("使用可能") { ForEach(model.available) { AvailableRow(item: $0) } }
            }
            if !model.credits.isEmpty {
                section("クレジット", trailing: "時間では戻りません") { ForEach(model.credits) { CreditRow(item: $0) } }
            }
            Divider()
            HStack {
                Button { Task { await model.refreshAll() } } label: { Label("すべて更新", systemImage: "arrow.clockwise") }
                    .help("すべてのサービスを更新します（通信します）")
                Spacer()
                Button("管理…") {
                    openWindow(id: "manage")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Button("終了") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .padding(12)
        }
        .frame(width: 360)
    }

    @ViewBuilder
    private func section<C: View>(_ title: String, trailing: String? = nil, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let trailing { Text(trailing).font(.caption).foregroundStyle(.secondary) }
            }
            content()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        Divider()
    }
}

private struct RowFrame<Trailing: View>: View {
    @EnvironmentObject var model: AppModel
    let item: Item
    let subtitle: String
    var glyph: Bool = true
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            if glyph {
                // 取得に失敗しているときは、「使用可能」の印にしない（古い数字を、正しいように見せない）。
                Group {
                    if item.fetchError != nil, item.snapshot != nil, item.state == .available {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    } else {
                        StateGlyph(state: item.state)
                    }
                }
                .frame(width: 18)
            }
            AppIconView(service: item.service)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(item.title).lineLimit(1)
                    if item.isBusiness { Text("法人").font(.caption2).foregroundStyle(.secondary) }
                }
                Text(model.errors[item.id] ?? subtitle)
                    .font(.caption).foregroundStyle(model.errors[item.id] == nil ? Color.secondary : Color.red)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            trailing()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct LimitedRow: View {
    @EnvironmentObject var model: AppModel
    let item: Item
    var body: some View {
        let until: Date = { if case .limited(let d) = item.state { return d }; return model.now }()
        let label = item.snapshot?.windows.filter { $0.isExhausted }.max { ($0.resetsAt ?? .distantPast) < ($1.resetsAt ?? .distantPast) }?.label ?? ""
        RowFrame(item: item, subtitle: "\(label) · \(formatClock(until, now: model.now)) ごろ") {
            Text(formatRemaining(until: until, now: model.now)).fontWeight(.semibold)
        }
    }
}

private struct StaleRow: View {
    @EnvironmentObject var model: AppModel
    let item: Item
    var body: some View {
        RowFrame(item: item, subtitle: "リセット目安です。必要なら再確認してください") {
            RefreshButton(item: item)
        }
    }
}

private struct AvailableRow: View {
    @EnvironmentObject var model: AppModel
    let item: Item
    var body: some View {
        let sub: String = {
            if item.state == .unset { return "まだ取得していません" }
            guard let w = item.snapshot?.windows.filter({ !$0.isExhausted }).min(by: { ($0.remainingPercent ?? 100) < ($1.remainingPercent ?? 100) }) else { return "" }
            if let r = w.resetsAt { return "\(w.label) · \(formatClock(r, now: model.now)) リセット" }
            return w.label
        }()
        RowFrame(item: item, subtitle: sub) {
            if item.state == .unset {
                RefreshButton(item: item)
            } else if item.fetchError != nil, let at = item.snapshot?.fetchedAt {
                Text("\(formatClock(at, now: model.now)) 時点").foregroundStyle(.orange)
            } else {
                Text(item.snapshot.flatMap(availableSummary) ?? "").foregroundStyle(.secondary)
            }
        }
    }
}

private struct CreditRow: View {
    @EnvironmentObject var model: AppModel
    let item: Item
    var body: some View {
        let credit = item.snapshot?.credit
        let sub: String = {
            guard let credit else { return "未取得" }
            if let r = credit.resetsAt { return "予算 · \(formatRemaining(until: r, now: model.now))で戻る" }
            return credit.note ?? ""
        }()
        RowFrame(item: item, subtitle: sub, glyph: false) {
            HStack(spacing: 6) {
                Text(credit.map(formatMoney) ?? "—").fontWeight(.semibold).monospacedDigit()
                RefreshButton(item: item)
                Button { if let u = model.paymentURL(item.account) { NSWorkspace.shared.open(u) } } label: {
                    Image(systemName: "plus")
                }
                .help("支払いページを開く").accessibilityLabel("支払いページを開く")
            }
        }
    }
}

/// くるくる回る表示は使わない。取得中は無効にするだけ。
struct RefreshButton: View {
    @EnvironmentObject var model: AppModel
    let item: Item
    var body: some View {
        Button { Task { await model.refresh(item.account) } } label: { Image(systemName: "arrow.clockwise") }
            .disabled(model.refreshing.contains(item.id))
            .help("更新（通信します）").accessibilityLabel("更新")
    }
}
