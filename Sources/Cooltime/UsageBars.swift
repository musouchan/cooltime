import SwiftUI
import CooltimeCore

/// シンプルな残りの棒。埋まっている長さが「残り」（満タン＝たっぷり）。
struct RemainingBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(tint)
                    .frame(width: fraction > 0 ? max(8, geo.size.width * min(1, fraction)) : 0)
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

/// 1つの枠（5時間枠・週の枠など）を、1行＋残りの棒で見せる。
/// 左に枠の名前、右に「残り87% · 17:20 リセット」。リセットの書き方は、設定で選べる（既定は日付と時刻。「あと4時間12分」も選べる）。
struct WindowBarRow: View {
    let window: UsageWindow
    let now: Date
    var dimmed = false
    @AppStorage(ResetTimeStyle.key) private var timeStyle = ResetTimeStyle.absolute.rawValue

    private var remaining: Double? { window.isExhausted ? 0 : window.remainingPercent }

    private var tint: Color {
        guard let r = remaining else { return .gray }
        if r < 10 { return .red }
        if r < 30 { return .orange }
        return .accentColor
    }

    private var summary: String {
        if let reset = window.resetsAt, reset <= now { return "リセット目安を過ぎた" }
        var parts: [String] = []
        if window.isExhausted {
            parts.append("尽きた")
        } else if let count = window.remainingCount {
            parts.append("残り\(Int(count.rounded()))")
        } else if let p = window.remainingPercent {
            parts.append("残り\(Int(p.rounded()))%")
        }
        if let reset = window.resetsAt {
            parts.append((ResetTimeStyle(rawValue: timeStyle) ?? .absolute).text(for: reset, now: now))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.label).font(.callout)
                Spacer(minLength: 8)
                Text(summary).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            if let r = remaining {
                RemainingBar(fraction: r / 100, tint: tint).padding(.top, 4)
            }
        }
        .opacity(dimmed ? 0.5 : 1)
        .accessibilityElement(children: .combine)
    }
}
