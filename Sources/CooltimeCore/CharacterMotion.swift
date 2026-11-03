import Foundation

/// キャラクターの状態（メニューバーの3つの状態）。
public enum CharacterState: String, CaseIterable, Sendable {
    case ok, limit, fail
}

/// ある時刻での、1つのグループ（root / look / eyes / zz）の変形。
public struct GroupTransform: Equatable, Sendable {
    public var tx = 0.0
    public var ty = 0.0
    /// 度。時計回りが正（SVG と同じ）。
    public var rotate = 0.0
    public var scaleY = 1.0
    public var opacity = 1.0
    public init() {}
}

/// characters/motion.json を読んで、時刻から変形を計算する。画面に依存しない（テストできる）。
public struct CharacterMotion: Sendable {
    struct Target: Sendable {
        var duration: Double
        var linear: Bool
        var keys: [(percent: Double, values: [String: Double])]
    }

    private var targets: [String: [String: Target]] = [:]

    public init?(json: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let states = root["states"] as? [String: Any] else { return nil }
        for (state, value) in states {
            guard let targetMap = (value as? [String: Any])?["targets"] as? [String: Any] else { continue }
            for (group, raw) in targetMap {
                guard let t = raw as? [String: Any], let duration = t["duration_s"] as? Double, duration > 0,
                      let kf = t["keyframes"] as? [String: [String: Double]] else { continue }
                let keys = kf.compactMap { k, v in Double(k).map { (percent: $0, values: v) } }.sorted { $0.percent < $1.percent }
                guard keys.count >= 2 else { continue }
                targets[state, default: [:]][group] = Target(duration: duration, linear: (t["easing"] as? String) == "linear", keys: keys)
            }
        }
    }

    /// その状態で動かすグループ。
    public func groups(state: CharacterState) -> [String] {
        (targets[state.rawValue] ?? [:]).keys.sorted()
    }

    /// 動きが1周する時間（秒）。静止している状態は nil。
    public func period(state: CharacterState) -> Double? {
        (targets[state.rawValue] ?? [:]).values.map(\.duration).max()
    }

    public func transform(state: CharacterState, group: String, at time: Double) -> GroupTransform {
        var out = GroupTransform()
        guard let t = targets[state.rawValue]?[group] else { return out }
        let phase = (time.truncatingRemainder(dividingBy: t.duration) + t.duration).truncatingRemainder(dividingBy: t.duration) / t.duration * 100
        var lo = t.keys[0], hi = t.keys[t.keys.count - 1]
        for i in 0..<(t.keys.count - 1) where phase >= t.keys[i].percent && phase <= t.keys[i + 1].percent {
            lo = t.keys[i]; hi = t.keys[i + 1]
            break
        }
        let span = hi.percent - lo.percent
        let u = span > 0 ? min(1, max(0, (phase - lo.percent) / span)) : 0
        let e = t.linear ? u : u * u * (3 - 2 * u)  // ease-in-out（なめらかに始まり、なめらかに終わる）
        func value(_ name: String, _ def: Double) -> Double {
            let a = lo.values[name] ?? def, b = hi.values[name] ?? def
            return a + (b - a) * e
        }
        out.tx = value("translateX", 0)
        out.ty = value("translateY", 0)
        out.rotate = value("rotate", 0)
        out.scaleY = value("scaleY", 1)
        out.opacity = value("opacity", 1)
        return out
    }
}
