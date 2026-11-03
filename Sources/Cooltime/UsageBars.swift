import SwiftUI
import CooltimeCore

/// 残りの棒。埋まっている長さが「残り」（満タン＝たっぷり）。
/// 色だけに頼らない: 数字（残り○%）と、尽きたときの文字（尽きた）も、いつも一緒に出す。
struct RemainingBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(tint)
                    .frame(width: fraction > 0 ? max(6, geo.size.width * min(1, fraction)) : 0)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// 1つの枠（5時間枠・週の枠など）を、1行＋棒で見せる。
/// 左に枠の名前、右に「残り87% · 17:20 リセット」。リセットは、日付と時刻（「あと○時間」の言い方はしない）。
struct WindowBarRow: View {
    let window: UsageWindow
    let now: Date
    var dimmed = false

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
        if let reset = window.resetsAt { parts.append("\(formatClock(reset, now: now)) リセット") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.label).font(.callout)
                Spacer(minLength: 8)
                Text(summary).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            if let r = remaining { RemainingBar(fraction: r / 100, tint: tint) }
        }
        .opacity(dimmed ? 0.5 : 1)
        .accessibilityElement(children: .combine)
    }
}
