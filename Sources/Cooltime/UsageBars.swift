import SwiftUI
import CooltimeCore

/// 残りの「おばけ散歩」。おばけが、残りの位置にいる（右＝たっぷり、左＝尽きた）。
/// 表情で、状態が分かる: 目が開いている／あたふた（残り10%未満）／眠る（尽きた）。
/// 色（青・オレンジ・赤）は補助。数字（残り○%）と「尽きた」の文字も、いつも一緒に出す。
struct GhostWalk: View {
    let fraction: Double
    let tint: Color

    private var mood: GhostMood {
        if fraction <= 0 { return .sleep }
        return fraction < 0.1 ? .worry : .open
    }

    var body: some View {
        GeometryReader { geo in
            let x0: CGFloat = 14, x1 = geo.size.width - 14
            let pos = x0 + (x1 - x0) * CGFloat(min(1, max(0, fraction)))
            let line = geo.size.height - 9          // 道の高さ
            let gw: CGFloat = 22, gh: CGFloat = 26

            // 道（点線）と、歩いてきたところ（太い線）
            Path { p in p.move(to: CGPoint(x: x0, y: line)); p.addLine(to: CGPoint(x: x1, y: line)) }
                .stroke(Color.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [0.1, 6]))
            if fraction > 0 {
                Path { p in p.move(to: CGPoint(x: x0, y: line)); p.addLine(to: CGPoint(x: pos, y: line)) }
                    .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }

            GhostView(mood: mood, fill: fraction <= 0 ? Color.primary.opacity(0.85) : .primary)
                .frame(width: gw, height: gh)
                .position(x: pos, y: line - gh / 2 + 4)
            if fraction <= 0 {
                ZZShape().fill(Color.primary).frame(width: 7, height: 7).position(x: pos + 9, y: line - gh - 1)
            }
            if fraction >= 0.1 && fraction < 0.3 {
                SweatDropShape().fill(tint).frame(width: 5, height: 7).position(x: pos + gw / 2 + 3, y: line - gh + 6)
            }
        }
        .frame(height: 40)
        .accessibilityHidden(true)
    }
}

/// 1つの枠（5時間枠・週の枠など）を、1行＋おばけ散歩で見せる。
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
            if let r = remaining { GhostWalk(fraction: r / 100, tint: tint) }
        }
        .opacity(dimmed ? 0.5 : 1)
        .accessibilityElement(children: .combine)
    }
}
