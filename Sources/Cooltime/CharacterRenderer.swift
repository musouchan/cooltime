import AppKit
import CooltimeCore

/// キャラクターの設定（管理画面で選ぶ）。
enum MotionSetting: String, CaseIterable, Identifiable {
    case full, sometimes, still
    var id: String { rawValue }
    var label: String {
        switch self {
        case .full: return "動く"
        case .sometimes: return "ときどきだけ"
        case .still: return "止める"
        }
    }
}

/// 残りの棒と、振り返りのグラフの見た目。既定はシンプル。メニューバーは、いつもシンプル。
enum DisplayStyle: String, CaseIterable, Identifiable {
    case simple, ghost
    static let key = "displayStyle"
    var id: String { rawValue }
    var label: String { self == .simple ? "シンプル" : "おばけ" }
}

/// リセットの書き方。既定は日時（「17:20 リセット」）。選べる。
enum ResetTimeStyle: String, CaseIterable, Identifiable {
    case absolute, relative
    static let key = "resetTimeStyle"
    var id: String { rawValue }
    var label: String { self == .absolute ? "日時" : "あと○時間" }

    /// 例: 「17:20 リセット」「11/7 17:00 リセット」／「あと4時間12分」
    func text(for reset: Date, now: Date) -> String {
        switch self {
        case .absolute: return "\(formatClock(reset, now: now)) リセット"
        case .relative: return formatRemaining(until: reset, now: now)
        }
    }
}

enum CharacterPrefs {
    static let characterKey = "character"
    static let motionKey = "characterMotion"
    /// 低電力モードのときも、フルに動かす（既定はオフ。仕様は、まばたきだけ）。
    static let lowPowerKey = "characterMotionInLowPower"
    /// メニューバーが混んでいて隠れるときのための、せまい表示（アイコンなし・短い文字）。
    static let compactKey = "menuBarCompact"

    static var characterID: String {
        let v = UserDefaults.standard.string(forKey: characterKey) ?? "bunny"
        return CharacterData.ids.contains(v) ? v : "bunny"
    }
    static var menuBarCompact: Bool { UserDefaults.standard.bool(forKey: compactKey) }
    static var motionInLowPower: Bool { UserDefaults.standard.bool(forKey: lowPowerKey) }
    static var motion: MotionSetting {
        MotionSetting(rawValue: UserDefaults.standard.string(forKey: motionKey) ?? "") ?? .full
    }
}

/// キャラクターを、Core Graphics で描く。
/// 絵は `CharacterData`（SVG から作ったパスの列）、動きは `CharacterMotion`（motion.json）。
/// 描いた画像は、コマごとに使い回す。1色のテンプレート画像にして、ライト／ダークに自動で合わせる。
@MainActor
enum CharacterRenderer {
    static let fps = 8.0
    static let motion = CharacterMotion(json: Data(CharacterData.motionJSON.utf8))!

    private static var images: [String: NSImage] = [:]
    private static var paths: [String: CGPath] = [:]

    /// `time` は秒（コマは 1/8 秒に丸める）。`only` を渡すと、そのグループだけ動かす（まばたきだけ、など）。
    static func image(id: String, state: CharacterState, time: Double, only: Set<String>? = nil, points: CGFloat = 18) -> NSImage {
        let frame = Int((time * fps).rounded(.down))
        let key = "\(id)|\(state.rawValue)|\(frame)|\(only?.sorted().joined(separator: ",") ?? "*")|\(Int(points))"
        if let hit = images[key] { return hit }
        if images.count > 900 { images.removeAll(keepingCapacity: true) }  // 使い回しのための置き場。増えすぎたら空にする

        let scale = 2  // 2倍（Retina）。1倍の画面でも、縮めて表示される
        let px = Int(points) * scale
        let image = NSImage(size: NSSize(width: points, height: points))
        if let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0),
           let gc = NSGraphicsContext(bitmapImageRep: rep) {
            rep.size = NSSize(width: points, height: points)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = gc
            draw(id: id, state: state, time: Double(frame) / fps, only: only, in: gc.cgContext, pixels: CGFloat(px))
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(rep)
        }
        image.isTemplate = true
        images[key] = image
        return image
    }

    private static func draw(id: String, state: CharacterState, time: Double, only: Set<String>?, in ctx: CGContext, pixels px: CGFloat) {
        let key = "\(id)-\(state.rawValue)"
        guard let elements = CharacterData.shapes[key], let origins = CharacterData.origins[key] else { return }

        // SVG と同じ向き（y が下向き、viewBox は -6 -6 112 112）に座標を合わせる
        ctx.translateBy(x: 0, y: px)
        ctx.scaleBy(x: 1, y: -1)
        ctx.scaleBy(x: px / 112, y: px / 112)
        ctx.translateBy(x: 6, y: 6)

        for el in elements {
            ctx.saveGState()
            var alpha = el.opacity
            for group in el.chain {
                let t = (only == nil || only!.contains(group)) ? motion.transform(state: state, group: group, at: time) : GroupTransform()
                let o = origins[group] ?? [0, 0]
                ctx.translateBy(x: t.tx, y: t.ty)
                ctx.translateBy(x: o[0], y: o[1])
                ctx.rotate(by: t.rotate * .pi / 180)
                ctx.scaleBy(x: 1, y: t.scaleY)
                ctx.translateBy(x: -o[0], y: -o[1])
                alpha *= t.opacity
            }
            ctx.setAlpha(alpha)
            // 「抜き」は、描いたところを透明にくり抜く（目・鼻・口）
            ctx.setBlendMode(el.cutout ? .destinationOut : .normal)
            let black = CGColor(gray: 0, alpha: 1)
            ctx.setFillColor(black)
            ctx.setStrokeColor(black)
            let path = cgPath(el.path)
            if el.fill {
                ctx.addPath(path)
                ctx.fillPath()
            }
            if el.stroke > 0 {
                ctx.addPath(path)
                ctx.setLineWidth(el.stroke)
                ctx.setLineCap(el.round ? .round : .butt)
                ctx.setLineJoin(el.round ? .round : .miter)
                ctx.strokePath()
            }
            ctx.restoreGState()
        }
    }

    /// "M x y L x y C x1 y1 x2 y2 x y Z" を CGPath にする。
    private static func cgPath(_ text: String) -> CGPath {
        if let hit = paths[text] { return hit }
        let p = CGMutablePath()
        let tokens = text.split(separator: " ")
        var i = 0
        func num() -> CGFloat { defer { i += 1 }; return CGFloat(Double(tokens[i]) ?? 0) }
        while i < tokens.count {
            let cmd = tokens[i]; i += 1
            switch cmd {
            case "M": p.move(to: CGPoint(x: num(), y: num()))
            case "L": p.addLine(to: CGPoint(x: num(), y: num()))
            case "C":
                let c1 = CGPoint(x: num(), y: num()), c2 = CGPoint(x: num(), y: num()), e = CGPoint(x: num(), y: num())
                p.addCurve(to: e, control1: c1, control2: c2)
            case "Z": p.closeSubpath()
            default: break
            }
        }
        paths[text] = p
        return p
    }
}
