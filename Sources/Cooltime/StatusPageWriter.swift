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

    // MARK: スマホのウィジェット（Scriptable）

    static let widgetKey = "statusWidgetEnabled"
    static var widgetEnabled: Bool { UserDefaults.standard.bool(forKey: widgetKey) }

    /// iPhone の Scriptable アプリの、iCloud のフォルダ（iPhone に Scriptable を入れて iCloud をオンにすると、Mac にも現れる）。
    static var scriptableFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/iCloud~dk~simonbs~Scriptable/Documents", isDirectory: true)
    }

    /// ウィジェットが読む JSON と、ウィジェットのスクリプト（Cooltime.js）を、Scriptable のフォルダに書く。
    @discardableResult
    static func writeWidget(_ entries: [StatusEntry], now: Date) -> String? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: scriptableFolder.path) else {
            return "Scriptable のフォルダが見つかりません。iPhone に Scriptable アプリを入れ、iCloud をオンにして開くと、Mac にも現れます。"
        }
        do {
            try renderStatusJSON(entries, generatedAt: now)
                .write(to: scriptableFolder.appendingPathComponent("cooltime-status.json"), options: .atomic)
            // スクリプトは、同梱のものが新しいときだけ置き直す（毎分は書かない）
            if let src = Bundle.main.url(forResource: "cooltime-widget", withExtension: "js"),
               let data = try? Data(contentsOf: src) {
                let dst = scriptableFolder.appendingPathComponent("Cooltime.js")
                if (try? Data(contentsOf: dst)) != data { try data.write(to: dst, options: .atomic) }
            }
            return nil
        } catch {
            return "書き出せませんでした: \(error.localizedDescription)"
        }
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
