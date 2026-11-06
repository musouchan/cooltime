import Foundation

/// 自分宛ての iMessage を送る（「メッセージ」アプリに、AppleScript で頼む）。
/// 文面と宛先は、スクリプトに文字列として埋め込まず、引数で渡す（引用符などで壊れないように）。
enum IMessageNotifier {
    static let enabledKey = "notifyRecoveryEnabled"
    static let handleKey = "notifyHandle"

    enum SendError: LocalizedError {
        case noHandle
        case failed(String)
        var errorDescription: String? {
            switch self {
            case .noHandle: return "宛先（自分の電話番号か Apple ID のメールアドレス）を入れてください。"
            case .failed(let m): return "送れませんでした: \(m)"
            }
        }
    }

    private static let script = [
        "on run argv",
        "tell application \"Messages\"",
        "set s to 1st account whose service type = iMessage",
        "set b to participant (item 1 of argv) of s",
        "send (item 2 of argv) to b",
        "end tell",
        "end run",
    ]

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    static var handle: String { (UserDefaults.standard.string(forKey: handleKey) ?? "").trimmingCharacters(in: .whitespaces) }

    static func send(_ text: String, to handle: String) async throws {
        let h = handle.trimmingCharacters(in: .whitespaces)
        guard !h.isEmpty else { throw SendError.noHandle }
        try await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = script.flatMap { ["-e", $0] } + [h, text]
            let err = Pipe()
            p.standardError = err
            p.standardOutput = Pipe()
            do { try p.run() } catch { throw SendError.failed(error.localizedDescription) }
            p.waitUntilExit()
            guard p.terminationStatus == 0 else {
                let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                throw SendError.failed(msg.isEmpty ? "「メッセージ」へのアクセスが許可されていないか、宛先が見つかりません" : msg)
            }
        }.value
    }
}
