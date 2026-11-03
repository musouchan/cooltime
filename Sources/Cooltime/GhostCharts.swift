import SwiftUI

/// 「おばけ積み」: 1日（または1時間）ごとに、おばけを積み上げる。1匹＝○%分。
/// 上限に当たった日は、赤いおばけになり、いちばん上のおばけが眠る。使っていない日は、薄いおばけが眠っている。
struct GhostStackChart: View {
    struct Column: Identifiable {
        let id: Int
        let label: String?
        let value: Double
        let limit: Bool
    }

    let columns: [Column]
    let unit: Double
    /// 日の表示（1時間ごと）。使っていない時間は、何も描かない（夜が、おばけだらけにならないように）。
    var dayView = false

    var body: some View {
        GeometryReader { geo in
            let n = max(1, columns.count)
            let slot = geo.size.width / CGFloat(n)
            let labelH: CGFloat = 18, topH: CGFloat = 26
            let plotH = geo.size.height - labelH - topH
            let maxUnits = max(1, columns.map { units($0.value) }.max() ?? 1)
            // おばけの高さ: 上限（22）、積める高さ、列の幅、の一番小さいもの。体は、少し縦長（幅 ＝ 高さ × 0.92）
            let gh = min(22, plotH / CGFloat(maxUnits), (slot - 3) / 0.92)
            let gw = gh * 0.92

            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(columns) { c in
                        column(c, gw: gw, gh: gh)
                            .frame(width: slot, height: plotH + topH, alignment: .bottom)
                    }
                }
                Rectangle().fill(Color.secondary.opacity(0.35)).frame(height: 1.5)
                HStack(spacing: 0) {
                    ForEach(columns) { c in
                        Text(c.label ?? "").font(.caption2).foregroundStyle(.secondary)
                            .frame(width: slot, height: labelH)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    private func units(_ v: Double) -> Int { v > 0 ? max(1, Int(ceil(v / unit - 1e-9))) : 0 }

    private var summary: String {
        let hits = columns.filter(\.limit).count
        let total = columns.map(\.value).reduce(0, +)
        return "使った量の合計 \(Int(total.rounded()))%分。上限に当たった回数 \(hits)"
    }

    @ViewBuilder
    private func column(_ c: Column, gw: CGFloat, gh: CGFloat) -> some View {
        let n = units(c.value)
        VStack(spacing: 0) {
            if c.limit {
                Text("上限").font(.system(size: 10, weight: .bold)).foregroundStyle(.red)
                ZZShape().fill(Color.red).frame(width: max(5, gw * 0.4), height: max(5, gw * 0.4)).padding(.bottom, 2)
            }
            if n == 0 {
                if !dayView {
                    GhostView(mood: .sleep, fill: Color.primary.opacity(0.3)).frame(width: gw * 0.8, height: gh * 0.8)
                }
            } else {
                ForEach(0..<n, id: \.self) { k in
                    // いちばん上（k == 0）が、眠る（上限の日だけ）
                    GhostView(mood: c.limit && k == 0 ? .sleep : .open, fill: c.limit ? .red : .primary)
                        .frame(width: gw, height: gh)
                }
            }
        }
    }
}

/// 時間帯（0〜23時）ごとの、おばけの大きさ。使うほど大きい。使っていない時間は、小さく薄く眠っている。
struct GhostSizeRow: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let slot = geo.size.width / 24
            let maxV = max(values.max() ?? 0, 0.0001)
            let labelH: CGFloat = 16
            let plotH = geo.size.height - labelH
            let maxS = min(plotH / 1.08, slot * 1.25)
            let minS = min(8, maxS * 0.5)

            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(0..<24, id: \.self) { h in
                        let v = h < values.count ? values[h] : 0
                        let s = v > 0 ? minS + (maxS - minS) * CGFloat(v / maxV) : minS
                        GhostView(mood: v > 0 ? .open : .sleep, fill: v > 0 ? .primary : Color.primary.opacity(0.3))
                            .frame(width: s, height: s * 1.08)
                            .frame(width: slot, height: plotH, alignment: .bottom)
                    }
                }
                HStack(spacing: 0) {
                    ForEach(0..<24, id: \.self) { h in
                        Text(h % 3 == 0 ? "\(h)" : "").font(.caption2).foregroundStyle(.secondary)
                            .frame(width: slot, height: labelH)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
