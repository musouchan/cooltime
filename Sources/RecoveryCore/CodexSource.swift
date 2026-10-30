import Foundation

/// `codex app-server` に問い合わせて、5時間枠・週の枠と戻る時刻を得る。
///
/// 注意: 応答の項目名は公式ドキュメントの要約から組み立てている。実機で必ず確認すること。
/// そのため解析はゆるく書いてあり、想定と違うときは数字を作らずエラーにする。
public struct CodexSource: Sendable {
    public init() {}

    public func fetch() async throws -> SourceResult {
        guard let path = Self.locateCodex() else { throw SourceError.notInstalled("codex") }
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global().async {
                do { cont.resume(returning: try Self.run(path: path)) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    static func locateCodex() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "command -v codex"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        let s = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (s?.isEmpty == false) ? s : nil
    }

    private static func run(path: String) throws -> SourceResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = ["app-server"]
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = FileHandle.nullDevice
        try p.run()

        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: killer)
        defer { killer.cancel(); if p.isRunning { p.terminate() } }

        func send(_ object: [String: Any]) throws {
            var d = try JSONSerialization.data(withJSONObject: object)
            d.append(0x0A)
            try inPipe.fileHandleForWriting.write(contentsOf: d)
        }
        var buffer = Data()
        func readResponse(id: Int) throws -> [String: Any] {
            while true {
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let line = buffer[buffer.startIndex..<nl]
                    buffer.removeSubrange(buffer.startIndex...nl)
                    if let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                       (obj["id"] as? Int) == id { return obj }
                }
                let chunk = outPipe.fileHandleForReading.availableData
                if chunk.isEmpty { throw SourceError.notAvailable("codex が途中で終了しました（ログイン済みか確認してください）") }
                buffer.append(chunk)
            }
        }

        try send(["jsonrpc": "2.0", "id": 1, "method": "initialize",
                  "params": ["clientInfo": ["name": "cooltime", "version": "0.1"]]])
        _ = try readResponse(id: 1)
        try send(["jsonrpc": "2.0", "method": "initialized"])
        try send(["jsonrpc": "2.0", "id": 2, "method": "account/rateLimits/read"])
        let resp = try readResponse(id: 2)
        guard let result = resp["result"] as? [String: Any] else {
            throw SourceError.unexpectedResponse("result がありません")
        }
        return try parse(result)
    }

    // MARK: - 解析（テストできる）

    public static func parse(_ result: [String: Any], now: Date = Date()) throws -> SourceResult {
        let limits = (result["rateLimits"] as? [String: Any]) ?? (result["rate_limits"] as? [String: Any]) ?? result
        var windows: [WindowStatus] = []
        for (key, fallback) in [("primary", "5時間枠"), ("secondary", "週の枠")] {
            guard let w = limits[key] as? [String: Any] else { continue }
            guard let used = pick(w, ["usedPercent", "used_percent"]) else { continue }
            var resetsAt: Date?
            if let epoch = pick(w, ["resetsAt", "resets_at"]) {
                resetsAt = Date(timeIntervalSince1970: epoch)
            } else if let inSec = pick(w, ["resetsInSeconds", "resets_in_seconds"]) {
                resetsAt = now.addingTimeInterval(inSec)
            }
            guard let reset = resetsAt else { continue } // 戻る時刻が無い枠は載せない
            windows.append(WindowStatus(name: name(for: w, fallback: fallback),
                                        usedPercent: used, resetsAt: reset))
        }
        if windows.isEmpty { throw SourceError.unexpectedResponse("利用枠の項目が見つかりません") }
        return SourceResult(windows: windows)
    }

    private static func pick(_ d: [String: Any], _ keys: [String]) -> Double? {
        for k in keys { if let n = d[k] as? NSNumber { return n.doubleValue } }
        return nil
    }

    private static func name(for w: [String: Any], fallback: String) -> String {
        guard let mins = pick(w, ["windowDurationMins", "window_minutes"]) else { return fallback }
        if mins == 300 { return "5時間枠" }
        if mins == 10080 { return "週の枠" }
        return fallback
    }
}
