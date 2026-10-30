import SwiftUI
import AppKit
import RecoveryCore

struct PopoverView: View {
    @ObservedObject var store: Store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.configs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("まだ何も追加されていません").font(.system(size: 13, weight: .medium))
                    Text("「管理…」から、使っているサービスを選んでください。選ぶまで何も取得しません。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .padding(16)
            } else {
                section("制限中", rows: store.limitedRows)
                section("使用可能", rows: store.availableRows)
                creditSection
            }
            Divider()
            HStack {
                Spacer()
                Button("管理…") {
                    openWindow(id: "manager")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            .padding(10)
        }
        .frame(width: 360)
        .onAppear { store.tick() }
    }

    @ViewBuilder
    private func section(_ title: String, rows: [Row]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                ForEach(rows) { RowView(row: $0, now: store.now, store: store) }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
        }
    }

    @ViewBuilder
    private var creditSection: some View {
        let rows = store.creditRows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("クレジット").font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Text("時間では戻りません").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .foregroundStyle(.secondary)
                ForEach(rows) { RowView(row: $0, now: store.now, store: store) }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
    }
}

private struct RowView: View {
    let row: Row
    let now: Date
    @ObservedObject var store: Store

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: stateSymbol)
                .foregroundStyle(stateColor)
                .accessibilityHidden(true)
            Image(systemName: row.entry.symbol)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title).font(.system(size: 13)).lineLimit(1)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                if let err = store.error(for: row.id) {
                    Text(err).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            Text(trailing).font(.system(size: 13, weight: .medium)).monospacedDigit()
            if case .credit = row.state { creditButtons }
        }
    }

    private var creditButtons: some View {
        HStack(spacing: 6) {
            Button {
                Task { await store.refresh(row.config) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("残高を更新").accessibilityLabel("残高を更新")
            .disabled(store.isRefreshing(row.id))

            Button {
                store.openPayment(row.config)
            } label: {
                Image(systemName: "plus")
            }
            .help("支払いページを開く").accessibilityLabel("支払いページを開く")
            .disabled(URL(string: row.config.paymentURL) == nil)
        }
    }

    private var subtitle: String {
        var parts = [row.accountText].filter { !$0.isEmpty }
        switch row.state {
        case .limited(let at):
            if let w = row.snapshot?.result.windows.first(where: { $0.usedPercent >= 100 && $0.resetsAt == at }) {
                parts.append("\(w.name) ・ \(RemainingFormat.clock(at))")
            }
        case .resetEstimatePassed:
            parts.append("リセット目安です。必要なら再確認してください")
        case .available:
            if let w = row.snapshot?.result.windows.max(by: { $0.usedPercent < $1.usedPercent }) {
                parts.append(w.name)
            }
        default: break
        }
        return parts.joined(separator: " ・ ")
    }

    private var trailing: String {
        switch row.state {
        case .limited(let at): return RemainingFormat.text(until: at, now: now)
        case .resetEstimatePassed: return "目安を過ぎた"
        case .available(let pct): return "残り\(Int(pct.rounded()))%"
        case .credit(let c): return c.text
        case .noData: return ""
        }
    }

    // 色だけに頼らず、アイコンの形でも状態が分かるようにする。
    private var stateSymbol: String {
        switch row.state {
        case .limited: return "pause.circle"
        case .resetEstimatePassed: return "questionmark.circle"
        case .available: return "checkmark.circle"
        default: return "circle.dashed"
        }
    }

    private var stateColor: Color {
        switch row.state {
        case .limited: return .red
        case .resetEstimatePassed: return .orange
        case .available: return .green
        default: return .secondary
        }
    }
}
