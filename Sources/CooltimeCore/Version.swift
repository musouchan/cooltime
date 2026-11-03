import Foundation

public enum AppVersion {
    /// "v0.4.0" や "0.4.0" を比べる。remote のほうが新しいときだけ true。
    public static func isNewer(_ remote: String, than local: String) -> Bool {
        let r = parts(remote), l = parts(local)
        guard !r.isEmpty else { return false }
        for i in 0..<max(r.count, l.count) {
            let a = i < r.count ? r[i] : 0, b = i < l.count ? l[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    static func parts(_ v: String) -> [Int] {
        let t = v.hasPrefix("v") || v.hasPrefix("V") ? String(v.dropFirst()) : v
        let nums = t.split(separator: ".").prefix(3).map { Int($0.prefix { $0.isNumber }) }
        return nums.contains(where: { $0 == nil }) ? [] : nums.compactMap { $0 }
    }
}
