import Foundation

/// 時刻の取得元。テストでは FixedClock に差し替える。
public protocol Clock {
    var now: Date { get }
}

public struct SystemClock: Clock {
    public init() {}
    public var now: Date { Date() }
}

public final class FixedClock: Clock {
    public var now: Date
    public init(_ now: Date) { self.now = now }
    public func advance(by seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}
