import SwiftUI

/// おばけ（キャラクターと同じ体）の表情。
enum GhostMood {
    case open    // 目が開いている
    case worry   // あたふた（目と、小さく開いた口）
    case sleep   // 眠っている
    case cross   // 目が「×」
}

/// おばけの体。上は半円、裾は3つの波。
struct GhostShape: Shape {
    func path(in rect: CGRect) -> Path {
        let x = rect.minX, y = rect.minY, w = rect.width, h = rect.height
        let r = w / 2, b = min(w * 0.15, h * 0.25), yb = y + h - b
        let k: CGFloat = 0.5522847498
        var p = Path()
        p.move(to: CGPoint(x: x, y: y + r))
        p.addCurve(to: CGPoint(x: x + r, y: y), control1: CGPoint(x: x, y: y + r - k * r), control2: CGPoint(x: x + r - k * r, y: y))
        p.addCurve(to: CGPoint(x: x + w, y: y + r), control1: CGPoint(x: x + r + k * r, y: y), control2: CGPoint(x: x + w, y: y + r - k * r))
        p.addLine(to: CGPoint(x: x + w, y: yb))
        // 裾の波（右から左へ、3つ。下にふくらむ）
        for i in 0..<3 {
            let xr = x + w - CGFloat(i) * w / 3, xl = xr - w / 3
            p.addCurve(to: CGPoint(x: xl, y: yb), control1: CGPoint(x: xr, y: yb + b * 4 / 3), control2: CGPoint(x: xl, y: yb + b * 4 / 3))
        }
        p.closeSubpath()
        return p
    }
}

/// 目・口（体から、くり抜く部分）。
struct GhostFace: Shape {
    let mood: GhostMood

    func path(in rect: CGRect) -> Path {
        let w = rect.width, x = rect.minX, y = rect.minY
        let cy = y + w * 0.52, c1 = x + w * 0.34, c2 = x + w * 0.66, s = w * 0.075
        var fills = Path(), strokes = Path()
        switch mood {
        case .open, .worry:
            let r = max(0.8, w * (mood == .worry ? 0.1 : 0.08))
            fills.addEllipse(in: CGRect(x: c1 - r, y: cy - r, width: 2 * r, height: 2 * r))
            fills.addEllipse(in: CGRect(x: c2 - r, y: cy - r, width: 2 * r, height: 2 * r))
            if mood == .worry {
                fills.addEllipse(in: CGRect(x: x + w * 0.5 - w * 0.07, y: cy + w * 0.2 - w * 0.09, width: w * 0.14, height: w * 0.18))
            }
        case .sleep:
            for c in [c1, c2] {
                strokes.move(to: CGPoint(x: c - s, y: cy))
                strokes.addQuadCurve(to: CGPoint(x: c + s, y: cy), control: CGPoint(x: c, y: cy + s * 2.4))
            }
        case .cross:
            let k = s * 0.9
            for c in [c1, c2] {
                strokes.move(to: CGPoint(x: c - k, y: cy - k)); strokes.addLine(to: CGPoint(x: c + k, y: cy + k))
                strokes.move(to: CGPoint(x: c + k, y: cy - k)); strokes.addLine(to: CGPoint(x: c - k, y: cy + k))
            }
        }
        var out = fills
        if !strokes.isEmpty {
            out.addPath(strokes.strokedPath(StrokeStyle(lineWidth: max(1, w * 0.06), lineCap: .round, lineJoin: .round)))
        }
        return out
    }
}

/// 眠りの「z」。
struct ZZShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return p.strokedPath(StrokeStyle(lineWidth: max(1.2, rect.width * 0.22), lineCap: .round, lineJoin: .round))
    }
}

/// あたふたのときの、汗のしずく。
struct SweatDropShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, x = rect.minX, y = rect.minY
        var p = Path()
        p.move(to: CGPoint(x: x + w / 2, y: y))
        p.addCurve(to: CGPoint(x: x + w, y: y + h * 0.65), control1: CGPoint(x: x + w * 0.6, y: y + h * 0.2), control2: CGPoint(x: x + w, y: y + h * 0.4))
        p.addCurve(to: CGPoint(x: x, y: y + h * 0.65), control1: CGPoint(x: x + w, y: y + h), control2: CGPoint(x: x, y: y + h))
        p.addCurve(to: CGPoint(x: x + w / 2, y: y), control1: CGPoint(x: x, y: y + h * 0.4), control2: CGPoint(x: x + w * 0.4, y: y + h * 0.2))
        return p
    }
}

/// おばけ1匹。目は透明にくり抜くので、ライト／ダークのどちらでも、同じように見える。
struct GhostView: View {
    var mood: GhostMood = .open
    var fill: Color = .primary

    var body: some View {
        ZStack {
            GhostShape().fill(fill)
            GhostFace(mood: mood).fill(Color.black).blendMode(.destinationOut)
        }
        .compositingGroup()
        .accessibilityHidden(true)
    }
}
