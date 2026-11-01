import Foundation
import CooltimeCore

enum FetchError: LocalizedError {
    case noKey
    case http(Int)
    case network
    case codexNotFound
    case codexNoResponse
    case noFile

    var errorDescription: String? {
        switch self {
        case .noKey: return "APIキーが未設定です"
        case .http(let c): return c == 401 || c == 403 ? "認証に失敗しました（APIキーを確認）" : "取得に失敗しました（HTTP \(c)）"
        case .network: return "通信できませんでした"
        case .codexNotFound: return "Codex が見つかりません（ChatGPT アプリか Codex CLI が必要）"
        case .codexNoResponse: return "Codex から応答がありませんでした（ログイン済みか確認）"
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

struct FetchResult {
    var snapshot: Snapshot
    var identity: AccountIdentity?
}

enum Fetchers {
    /// Claude Code が手元に持つ設定ファイルから、メールアドレスだけを読む（通信なし）。
    static func claudeIdentity() -> AccountIdentity? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return ClaudeAccount.parse(data)
    }

    /// 手元のファイルを読むだけ（通信なし）。自動で読み直してよい。
    static func readClaude(slot: String) throws -> Snapshot {
        let url = Paths.statusline(slot: slot)
        guard let data = try? Data(contentsOf: url) else { throw FetchError.noFile }
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        return try ClaudeStatusline.parse(data, fetchedAt: mtime)
    }

    /// 通信を伴う取得。更新ボタンのときだけ呼ぶ。送り先は各サービスの公式の窓口だけ。
    static func fetch(account: Account, service: ServiceDef) async throws -> FetchResult {
        let now = Date()
        switch service.method {
        case .statuslineFile:
            return FetchResult(snapshot: try readClaude(slot: account.slot), identity: claudeIdentity())
        case .codexAppServer:
            let (limits, acct) = try await Task.detached { try Codex.query() }.value
            return FetchResult(snapshot: try CodexRateLimits.parse(limits, fetchedAt: now),
                               identity: acct.flatMap(CodexAccount.parse))
        case .apiKey:
            guard let key = Keychain.get(account.id), !key.isEmpty else { throw FetchError.noKey }
            let data: Data
            switch service.id {
            case "elevenlabs":
                data = try await get("https://api.elevenlabs.io/v1/user/subscription", headers: ["xi-api-key": key])
                return FetchResult(snapshot: try ElevenLabs.parse(data, fetchedAt: now), identity: nil)
            case "firecrawl":
                data = try await get("https://api.firecrawl.dev/v2/team/credit-usage", headers: bearer(key))
                return FetchResult(snapshot: try Firecrawl.parse(data, fetchedAt: now), identity: nil)
            case "vercel-ai-gateway":
                data = try await get("https://ai-gateway.vercel.sh/v1/credits", headers: bearer(key))
                return FetchResult(snapshot: try VercelAIGateway.parse(data, fetchedAt: now), identity: nil)
            case "openrouter":
                data = try await get("https://openrouter.ai/api/v1/key", headers: bearer(key))
                return FetchResult(snapshot: try OpenRouter.parse(data, fetchedAt: now), identity: nil)
            case "deepseek":
                data = try await get("https://api.deepseek.com/user/balance", headers: bearer(key))
                return FetchResult(snapshot: try DeepSeek.parse(data, fetchedAt: now), identity: nil)
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
    /// Codex の実行ファイルを探す。ChatGPT アプリに同梱のものを最優先で使い、
    /// 無ければ Homebrew / npm などの場所を見る。
    static func executable() -> URL? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
            "\(home)/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(home)/.npm-global/bin/codex",
            "\(home)/.bun/bin/codex",
            "\(home)/.local/bin/codex",
        ]
        return candidates.first { fm.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    /// 利用枠（id 2）とアカウント情報（id 3）の応答の行を返す。
    static func query() throws -> (limits: Data, account: Data?) {
        let p = Process()
        let exe = executable()
        if let exe {
            p.executableURL = exe
            p.arguments = ["app-server"]
        } else {
            // 見つからないときは、ログインシェル経由で PATH（npm / Homebrew など）から探す。
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-l", "-c", "exec codex app-server"]
        }
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
            #"{"id":3,"method":"account/read","params":{"refreshToken":false}}"#,
        ]
        for m in messages { stdin.fileHandleForWriting.write(Data((m + "\n").utf8)) }

        var buffer = Data()
        var got: [Int: Data] = [:]
        while true {
            let chunk = stdout.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: buffer.startIndex..<nl)
                buffer.removeSubrange(buffer.startIndex...nl)
                guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let id = obj["id"] as? Int, id == 2 || id == 3 else { continue }
                got[id] = line
                if id == 2 {
                    // アカウント情報は付けたし。待っても数秒まで。
                    DispatchQueue.global().asyncAfter(deadline: .now() + 3) { if p.isRunning { p.terminate() } }
                }
                if let l = got[2], got[3] != nil { return (l, got[3]) }
            }
        }
        if let l = got[2] { return (l, got[3]) }
        throw exe == nil ? FetchError.codexNotFound : FetchError.codexNoResponse
    }
}
