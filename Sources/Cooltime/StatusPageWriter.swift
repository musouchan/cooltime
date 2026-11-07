import Foundation
import CooltimeCore

/// スマホ用のページ（HTML）を、iCloud Drive の「Cooltime」フォルダに書き出す。
/// iPhone の「ファイル」アプリで開ける。外のサービスは使わず、残りと戻る時刻だけを書く（APIキーは書かない）。
enum StatusPageWriter {
    static let enabledKey = "statusPageEnabled"
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Cooltime", isDirectory: true)
    }
    static var file: URL { folder.appendingPathComponent("index.html") }

    /// iCloud Drive が使える（Mac で iCloud Drive がオン）か。
    static var iCloudDriveAvailable: Bool {
        FileManager.default.fileExists(atPath: folder.deletingLastPathComponent().path)
    }

    @discardableResult
    static func write(_ entries: [StatusEntry], now: Date) -> String? {
        guard iCloudDriveAvailable else { return "iCloud Drive が見つかりません（Mac の設定で iCloud Drive をオンにしてください）" }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try renderStatusPage(entries, generatedAt: now).write(to: file, atomically: true, encoding: .utf8)
            return nil
        } catch {
            return "書き出せませんでした: \(error.localizedDescription)"
        }
    }
}
