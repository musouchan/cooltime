import AppKit
import CooltimeCore

/// この Mac に、そのサービスのアプリや、ツールのファイルがあるか（あるかどうかだけ。中身は読まない）。
@MainActor
enum ServiceDetector {
    static func isInstalled(_ s: ServiceDef) -> Bool {
        if s.appBundleIDs.contains(where: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }) { return true }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return s.detectHomePaths.contains { exists(home, $0) }
    }

    /// 最後の部分が「*」で終わるときは、その前の文字で始まる名前が、あるか。
    private static func exists(_ home: URL, _ path: String) -> Bool {
        let fm = FileManager.default
        guard path.hasSuffix("*") else { return fm.fileExists(atPath: home.appendingPathComponent(path).path) }
        let url = home.appendingPathComponent(path)
        let prefix = String(url.lastPathComponent.dropLast())
        let names = (try? fm.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)) ?? []
        return names.contains { $0.hasPrefix(prefix) }
    }
}
