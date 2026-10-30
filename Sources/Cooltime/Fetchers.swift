import Foundation
import CooltimeCore

enum FetchError: LocalizedError {
    case noKey
    case http(Int)
    case network
    case codexNotFound
    case noFile

    var errorDescription: String? {
        switch self {
        case .noKey: return "APIキーが未設定です"
        case .http(let c): return c == 401 || c == 403 ? "認証に失敗しました（APIキーを確認）" : "取得に失敗しました（HTTP \(c)）"
        case .network: return "通信できませんでした"
        case .codexNotFound: return "Codex が見つかりません（ログイン済みか確認）"
        case .noFile: return "まだデータがありません（ステータスラインの設定が必要）"
        }
    }
}

enum Paths {
    static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("Cooltime", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static var state: URL { dir.appendingPathComponent("state.json") }
    static func statusline(slot: String) -> URL { dir.appendingPathComponent("claude-\(slot).json") }
}

enum Fetchers {
    /// 手元のファイルを読むだけ（通信なし）。自動で読み直してよい。
    static func readClaude(slot: String) throws -> Snapshot {
        let url = Paths.statusline(slot: slot)
        guard let data = try? Data(contentsOf: url) else { throw FetchError.noFile }
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        return try ClaudeStatusline.parse(data, fetchedAt: mtime)
    }

    /// 通信を伴う取得。更新ボタンのときだけ呼ぶ。送り先は各サービスの公式の窓口だけ。
    static func fetch(account: Account, service: ServiceDef) async throws -> Snapshot {
        let now = Date()
        switch service.method {
        case .statuslineFile:
            return try readClaude(slot: account.slot)
        case .codexAppServer:
            let line = try await Task.detached { try Codex.rateLimitsLine() }.value
            return try CodexRateLimits.parse(line, fetchedAt: now)
        case .apiKey:
            guard let key = Keychain.get(account.id), !key.isEmpty else { throw FetchError.noKey }
            let data: Data
            switch service.id {
            case "elevenlabs":
                data = try await get("https://api.elevenlabs.io/v1/user/subscription", headers: ["xi-api-key": key])
                return try ElevenLabs.parse(data, fetchedAt: now)
            case "firecrawl":
                data = try await get("https://api.firecrawl.dev/v2/team/credit-usage", headers: bearer(key))
                return try Firecrawl.parse(data, fetchedAt: now)
            case "vercel-ai-gateway":
                data = try await get("https://ai-gateway.vercel.sh/v1/credits", headers: bearer(key))
                return try VercelAIGateway.parse(data, fetchedAt: now)
            case "openrouter":
                data = try await get("https://openrouter.ai/api/v1/key", headers: bearer(key))
                return try OpenRouter.parse(data, fetchedAt: now)
            case "deepseek":
                data = try await get("https://api.deepseek.com/user/balance", headers: bearer(key))
                return try DeepSeek.parse(data, fetchedAt: now)
            default:
                throw ParseError.unsupported("未対応のサービスです")
            }
        }
    }

    private static func bearer(_ key: String) -> [String: String] { ["Authorization": "Bearer \(key)"] }

    private static func get(_ url: String, headers: [String: String]) async throws -> Data {
        var req = URLRequest(url: URL(string: url)!, timeoutInterval: 15)
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        // Cookie・キャッシュは使わない。
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpShouldSetCookies = false
        do {
            let (data, res) = try await URLSession(configuration: cfg).data(for: req)
            let code = (res as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else { throw FetchError.http(code) }
            return data
        } catch let e as FetchError {
            throw e
        } catch {
            throw FetchError.network
        }
    }
}

/// `codex app-server` に JSON-RPC（1行1メッセージ）で問い合わせる。
enum Codex {
    static func rateLimitsLine() throws -> Data {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // ログインシェル経由で、GUI アプリからは見えない PATH（npm / Homebrew）を拾う。
        p.arguments = ["-l", "-c", "exec codex app-server"]
        let stdin = Pipe(), stdout = Pipe()
        p.standardInput = stdin
        p.standardOutput = stdout
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { throw FetchError.codexNotFound }

        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 25, execute: killer)
        defer { killer.cancel(); if p.isRunning { p.terminate() } }

        let messages = [
            #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"cooltime","title":"Cooltime","version":"0.1.0"}}}"#,
            #"{"method":"initialized"}"#,
            #"{"id":2,"method":"account/rateLimits/read"}"#,
        ]
        for m in messages { stdin.fileHandleForWriting.write(Data((m + "\n").utf8)) }

        var buffer = Data()
        while true {
            let chunk = stdout.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: buffer.startIndex..<nl)
                buffer.removeSubrange(buffer.startIndex...nl)
                if let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                   (obj["id"] as? Int) == 2 {
                    return line
                }
            }
        }
        throw FetchError.codexNotFound
    }
}
