import Foundation
import CooltimeCore

/// Claude Code の settings.json にステータスラインを足す（本人が内容を見て同意したときだけ）。
enum StatuslineSetup {
    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }
    /// アプリを動かしても壊れないよう、スクリプトは Application Support に置く。
    static var scriptURL: URL { Paths.dir.appendingPathComponent("cooltime-statusline.sh") }
    /// 返事が終わったら、合図のファイルを更新するだけのフック（通信なし）。
    /// Cooltime 自身の確認（COOLTIME_USAGE_PROBE）では動かない。
    static let hookCommand = #"[ -n "$COOLTIME_USAGE_PROBE" ] || touch "$HOME/Library/Application Support/Cooltime/claude-ping""#

    static func isSet() -> Bool {
        StatuslineConfig.isSet(try? Data(contentsOf: settingsURL), scriptPath: scriptURL.path, hookCommand: hookCommand)
    }

    /// 変更内容（書き込みはしない）。
    static func preview() throws -> StatuslineConfig.Change {
        try StatuslineConfig.plan(existing: try? Data(contentsOf: settingsURL), scriptPath: scriptURL.path,
                                  hookCommand: hookCommand)
    }

    static func apply(_ change: StatuslineConfig.Change) throws {
        guard !change.alreadySet else { return }
        try installScript()
        try backupSettings()
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try change.newData.write(to: settingsURL, options: .atomic)
    }

    static func revert() throws {
        guard let data = try? Data(contentsOf: settingsURL),
              let back = try StatuslineConfig.revert(existing: data, scriptPath: scriptURL.path,
                                                     hookCommand: hookCommand) else { return }
        try backupSettings()
        try back.write(to: settingsURL, options: .atomic)
    }

    private static func installScript() throws {
        guard let src = Bundle.main.url(forResource: "cooltime-statusline", withExtension: "sh") else {
            throw ParseError.unsupported("記録スクリプトが見つかりません（アプリ版のみ対応）")
        }
        let fm = FileManager.default
        try? fm.removeItem(at: scriptURL)
        try fm.copyItem(at: src, to: scriptURL)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    }

    /// 元のファイルは、変更の前に必ずバックアップする。
    private static func backupSettings() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: settingsURL.path) else { return }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
        let backup = settingsURL.deletingLastPathComponent().appendingPathComponent("settings.json.cooltime-backup-\(stamp)")
        try fm.copyItem(at: settingsURL, to: backup)
    }
}
