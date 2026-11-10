import SwiftUI
import AppKit
import CooltimeCore

struct PopoverView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var actions: AppActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.accounts.isEmpty {
                Text("サービスが未設定です。「管理…」から、使っているものを追加してください。")
                    .font(.callout).foregroundStyle(.secondary).padding(16)
            }
            if !model.limited.isEmpty || !model.stale.isEmpty {
                section("制限中") {
                    ForEach(model.limited) { ServiceCard(item: $0, kind: .limited) }
                    ForEach(model.stale) { ServiceCard(item: $0, kind: .stale) }
                }
            }
            if !model.available.isEmpty {
                section("使用可能") { ForEach(model.available) { ServiceCard(item: $0, kind: .available) } }
            }
            if !model.credits.isEmpty {
                section("クレジット", trailing: "時間では戻りません") { ForEach(model.credits) { CreditRow(item: $0) } }
            }
            if !model.manualCredits.isEmpty {
                section("手動記録", trailing: "現在値ではありません") {
                    ForEach(model.manualCredits) { ManualCreditRow(item: $0) }
                }
            }
            Divider()
            HStack {
                Button { Task { await model.refreshAll() } } label: { Label("すべて更新", systemImage: "arrow.clockwise") }
                    .help("すべてのサービスを更新します（通信します）")
                Spacer()
                Button { actions.openReview() } label: { Image(systemName: "chart.bar") }
                    .help("振り返り").accessibilityLabel("振り返り")
                Button("管理…") { actions.openManage() }
                Button("終了") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .padding(12)
        }
        .frame(width: 360)
    }

    @ViewBuilder
    private func section<C: View>(_ title: String, trailing: String? = nil, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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

/// サービス1つ分。見出し（アイコン・名前・状態）と、枠ごとの棒。
/// 文字は最小限にして、棒と数字で、ひと目で分かるようにする。
private struct ServiceCard: View {
    enum Kind { case limited, available, stale }

    @EnvironmentObject var model: AppModel
    let item: Item
    let kind: Kind

    private var windows: [UsageWindow] { item.snapshot?.windows ?? [] }
    private var failed: Bool { item.fetchError != nil && item.snapshot != nil }
    private var dimmed: Bool { kind == .stale || failed }

    @ViewBuilder private var glyph: some View {
        switch kind {
        case .limited: Image(systemName: "pause.circle").foregroundStyle(.red)
        case .stale: Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
        case .available:
            if item.state == .unset { Image(systemName: "circle.dashed").foregroundStyle(.secondary) }
            else if failed { Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange) }
            else { Image(systemName: "checkmark.circle").foregroundStyle(.green) }
        }
    }

    @ViewBuilder private var trailing: some View {
        switch kind {
        case .limited:
            if case .limited(let until) = item.state {
                Text(formatRemaining(until: until, now: model.now)).fontWeight(.semibold).monospacedDigit()
            }
        case .stale: RefreshButton(item: item)
        case .available:
            if item.state == .unset { RefreshButton(item: item) }
            else if failed, let at = item.snapshot?.fetchedAt {
                Text("\(formatClock(at, now: model.now)) 時点").font(.caption).foregroundStyle(.orange)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                glyph.frame(width: 18)
                AppIconView(service: item.service, size: 20)
                Text(item.title).fontWeight(.medium).lineLimit(1)
                if item.isBusiness { Text("法人").font(.caption2).foregroundStyle(.secondary) }
                Spacer(minLength: 4)
                trailing
            }
            if let err = model.errors[item.id] {
                Text(err).font(.caption).foregroundStyle(.red).lineLimit(2)
            } else if kind == .stale {
                Text("リセット目安です。必要なら再確認してください").font(.caption).foregroundStyle(.secondary)
            } else if item.state == .unset {
                Text("まだ取得していません").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(windows.enumerated()), id: \.offset) { _, w in
                WindowBarRow(window: w, now: model.now, dimmed: dimmed)
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
            if let r = credit.resetsAt {
                let time = formatRemaining(until: r, now: model.now)
                if let note = credit.note { return "\(note) · \(time)で更新" }
                return "予算 · \(time)で戻る"
            }
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

/// 過去の観測値を表示する。自動取得の「クレジット」と混ぜない。
private struct ManualCreditRow: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var actions: AppActions
    let item: Item

    var body: some View {
        HStack(spacing: 8) {
            AppIconView(service: item.service)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).lineLimit(1)
                if let at = item.snapshot?.fetchedAt {
                    Text("\(formatClock(at, now: model.now)) に手動で確認")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("記録なし").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let c = item.snapshot?.credit {
                Text(formatMoney(c)).font(.callout).foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Button("編集") { actions.openManage() }
                .font(.caption)
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
