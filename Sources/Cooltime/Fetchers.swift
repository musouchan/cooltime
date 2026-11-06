import Foundation
import CooltimeCore

enum FetchError: LocalizedError {
    case noKey
    case http(Int)
    case network
    case codexNotFound
    case codexNoResponse
    case noFile
    case claudeNotFound
    case claudeFailed(String)

    var errorDescription: String? {
        switch self {
        case .noKey: return "APIキーが未設定です"
        case .http(let c): return c == 401 || c == 403 ? "認証に失敗しました（APIキーを確認）" : "取得に失敗しました（HTTP \(c)）"
        case .network: return "通信できませんでした"
        case .codexNotFound: return "Codex が見つかりません（ChatGPT アプリか Codex CLI が必要）"
        case .codexNoResponse: return "Codex から応答がありませんでした（ログイン済みか確認）"
        case .noFile: return "まだデータがありません（ステータスラインの設定が必要）"
        case .claudeNotFound: return "Claude Code（ターミナル版）が見つかりません"
        case .claudeFailed(let d): return "/usage を取得できませんでした（\(d)）"
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
    /// 使用状況の記録（枠の%と時刻だけ。会話の中身は持たない）。
    static var history: URL { dir.appendingPathComponent("history.json") }
    static func statusline(slot: String) -> URL { dir.appendingPathComponent("claude-\(slot).json") }
    /// Antigravity CLI statusline script writes only the quota object here (user opt-in).
    static var antigravityStatusline: URL { dir.appendingPathComponent("antigravity-quota.json") }
    /// Claude Code の Stop フックが更新する合図のファイル（中身は空）。
    static var claudePing: URL { dir.appendingPathComponent("claude-ping") }
}

struct FetchResult {
    var snapshot: Snapshot
    var identity: AccountIdentity?
    /// 取れたが問題があるとき（例: /usage が失敗して、古い記録を使った）。画面に出す。
    var warning: String?
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

    static func readAntigravity() throws -> Snapshot {
        let url = Paths.antigravityStatusline
        guard let data = try? Data(contentsOf: url) else { throw FetchError.noFile }
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        return try AntigravityStatusline.parse(data, fetchedAt: mtime)
    }

    /// 通信を伴う取得。更新ボタンのときだけ呼ぶ。送り先は各サービスの公式の窓口だけ。
    static func fetch(account: Account, service: ServiceDef) async throws -> FetchResult {
        let now = Date()
        switch service.method {
        case .manual:
            throw ParseError.unsupported("手動記録サービスは自動取得しません")
        case .statuslineFile:
            if service.id == "sheet-11" {
                // Antigravity CLI writes the official statusline quota JSON locally; no network/API call.
                return FetchResult(snapshot: try readAntigravity(), identity: nil)
            }
            // 既定のアカウントは、公式の Claude Code の /usage で、アカウント全体の使用量を取る。
            // 取れなければ、ステータスラインの記録に戻る。
            if account.slot == "default" {
                do {
                    let text = try await Task.detached { try ClaudeCLI.usage() }.value
                    return FetchResult(snapshot: try ClaudeUsageText.parse(text, now: now), identity: claudeIdentity())
                } catch {
                    // 失敗を隠さない。古い記録があれば表示は続けるが、理由を画面に出す。
                    if let s = try? readClaude(slot: account.slot) {
                        return FetchResult(snapshot: s, identity: claudeIdentity(), warning: error.localizedDescription)
                    }
                    throw error
                }
            }
            return FetchResult(snapshot: try readClaude(slot: account.slot), identity: claudeIdentity())
        case .codexAppServer:
            let (limits, acct) = try await Task.detached { try Codex.query() }.value
            return FetchResult(snapshot: try CodexRateLimits.parse(limits, fetchedAt: now),
                               identity: acct.flatMap(CodexAccount.parse))
        case .apiKey:
            guard let key = Keychain.get(account.id), !key.isEmpty else { throw FetchError.noKey }
            let data: Data
            switch service.id {
            case "figma-ai-usage":
                let config = try FigmaAIUsage.configuration(from: key)
                let period = DailyUsagePeriod.previousSevenDays(now: now, lagHours: 6)
                let snapshot = try await FigmaAIUsage.fetch(email: config.email, period: period, fetchedAt: now) { url in
                    try await get(url, headers: ["X-Figma-Token": config.token], allowRedirects: false)
                }
                return FetchResult(snapshot: snapshot, identity: nil)
            case "augment-credit-usage":
                let config = try AugmentCreditUsage.configuration(from: key)
                let period = DailyUsagePeriod.previousSevenDays(now: now, lagHours: 2)
                let snapshot = try await AugmentCreditUsage.fetch(email: config.email, period: period, fetchedAt: now) { url in
                    try await get(url, headers: bearer(config.token), allowRedirects: false)
                }
                return FetchResult(snapshot: snapshot, identity: nil)
            case "opencode-go-usage":
                let config = try OpenCodeGoUsage.configuration(from: key)
                data = try await get(config.url, headers: ["Authorization": config.authorization],
                                     allowRedirects: false, loopbackOnly: true)
                return FetchResult(snapshot: try OpenCodeGoUsage.parse(data, workspace: config.workspace, fetchedAt: now), identity: nil)
            case "huggingface-inference-usage":
                let config = try HuggingFaceUsage.configuration(from: key)
                let period = DailyUsagePeriod.previousSevenDays(now: now, lagHours: 2)
                let page = try await getUsagePage(HuggingFaceUsage.url(organization: config.organization, period: period), headers: bearer(config.token))
                return FetchResult(snapshot: try HuggingFaceUsage.parse(page.data, linkHeader: page.link, period: period, fetchedAt: now), identity: nil)
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
            case "runway":
                data = try await get("https://api.dev.runwayml.com/v1/organization",
                                     headers: bearer(key).merging(["X-Runway-Version": RunwayAPI.version]) { $1 })
                return FetchResult(snapshot: try RunwayAPI.parse(data, fetchedAt: now), identity: nil)
            case "luma":
                data = try await get("https://api.lumalabs.ai/dream-machine/v1/credits", headers: bearer(key))
                return FetchResult(snapshot: try LumaAI.parse(data, fetchedAt: now), identity: nil)
            case "stability":
                data = try await get("https://api.stability.ai/v1/user/balance", headers: bearer(key))
                return FetchResult(snapshot: try StabilityAI.parse(data, fetchedAt: now), identity: nil)
            case "apify":
                data = try await get("https://api.apify.com/v2/users/me/limits", headers: bearer(key))
                return FetchResult(snapshot: try Apify.parse(data, fetchedAt: now), identity: nil)
            case "serpapi":
                // SerpAPI は、キーを URL の末尾に付ける作り。ログには出さない。
                let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
                data = try await get("https://serpapi.com/account.json?api_key=\(encoded)", headers: [:])
                return FetchResult(snapshot: try SerpAPI.parse(data, fetchedAt: now), identity: nil)
            case "deepl":
                data = try await get(DeepL.endpoint(forKey: key), headers: ["Authorization": "DeepL-Auth-Key \(key)"])
                return FetchResult(snapshot: try DeepL.parse(data, fetchedAt: now), identity: nil)
            case "photoroom":
                data = try await get("https://image-api.photoroom.com/v1/account", headers: ["x-api-key": key])
                return FetchResult(snapshot: try Photoroom.parse(data, fetchedAt: now), identity: nil)
            case "meshy":
                data = try await get("https://api.meshy.ai/openapi/v1/balance", headers: bearer(key))
                return FetchResult(snapshot: try Meshy.parse(data, fetchedAt: now), identity: nil)
            case "sheet-168":
                data = try await get("https://server.headshotpro.com/api/v2/organization/credits", headers: bearer(key))
                return FetchResult(snapshot: try HeadshotProCredits.parse(data, fetchedAt: now), identity: nil)
            case "sheet-20":
                let cyclesData = try await get("https://api.devin.ai/v3/enterprise/consumption/cycles?first=200", headers: bearer(key))
                let cycle = try DevinEnterpriseUsage.currentCycle(in: cyclesData, now: now)
                let budgetsData = try await get("https://api.devin.ai/v3beta1/enterprise/usage-policies/budgets?first=200", headers: bearer(key))
                let usageURL = "https://api.devin.ai/v3/enterprise/consumption/daily?time_after=\(cycle.after)&time_before=\(cycle.before)"
                data = try await get(usageURL, headers: bearer(key))
                return FetchResult(snapshot: try DevinEnterpriseUsage.parse(cyclesData: cyclesData,
                                                                           budgetsData: budgetsData,
                                                                           consumptionData: data,
                                                                           now: now, fetchedAt: now), identity: nil)
            case "sheet-86":
                let limitData = try await get("https://api.openai.com/v1/organization/spend_limit", headers: bearer(key))
                let costsURL = OpenAIPlatformUsage.costsURL(now: now)
                data = try await get(costsURL, headers: bearer(key))
                return FetchResult(snapshot: try OpenAIPlatformUsage.parse(limitData: limitData,
                                                                           costsData: data,
                                                                           now: now, fetchedAt: now), identity: nil)
            case "sheet-87":
                let anthropicHeaders = ["x-api-key": key,
                                        "anthropic-version": AnthropicUsage.apiVersion,
                                        "anthropic-beta": AnthropicUsage.betaHeader]
                data = try await get(AnthropicUsage.costsURL(now: now), headers: anthropicHeaders)
                return FetchResult(snapshot: try AnthropicUsage.parse(data), identity: nil)
            case "sheet-90":
                let headers = bearer(key).merging(["Content-Type": "application/json"]) { $1 }
                let validation = try await get("https://management-api.x.ai/auth/management-keys/validation", headers: bearer(key))
                let teamID = try XAIUsage.teamID(from: validation)
                let body = try XAIUsage.usageRequestBody(now: now)
                data = try await postJSON(XAIUsage.usageURL(teamID: teamID), headers: headers, body: body)
                return FetchResult(snapshot: try XAIUsage.parse(data, fetchedAt: now), identity: nil)
            case "sheet-93":
                data = try await get(TogetherBilling.usageURL(now: now), headers: bearer(key))
                return FetchResult(snapshot: try TogetherBilling.parse(data, expectedMonth: TogetherBilling.monthString(now),
                                                                       fetchedAt: now), identity: nil)
            case "sheet-104":
                data = try await get("https://admin-api.exa.ai/team-management/credits", headers: ["x-api-key": key])
                return FetchResult(snapshot: try ExaCredits.parse(data, fetchedAt: now), identity: nil)
            case "sheet-112":
                data = try await get("https://context7.com/api/v2/usage?days=30", headers: bearer(key))
                return FetchResult(snapshot: try Context7Usage.parse(data, fetchedAt: now), identity: nil)
            case "browserbase-usage":
                let config = try BrowserbaseUsage.configuration(from: key)
                data = try await get(config.url, headers: ["X-BB-API-Key": config.apiKey], allowRedirects: false)
                return FetchResult(snapshot: try BrowserbaseUsage.parse(data, fetchedAt: now), identity: nil)
            case "langsmith-trace-usage":
                let config = try LangSmithUsage.configuration(from: key)
                let period = LangSmithUsage.period(endingBefore: now)
                let url = try LangSmithUsage.url(for: config.region, workspace: config.workspace, period: period)
                data = try await get(url, headers: ["x-api-key": config.apiKey], allowRedirects: false)
                return FetchResult(snapshot: try LangSmithUsage.parse(data, workspace: config.workspace, period: period,
                                                                      fetchedAt: now), identity: nil)
            case "datadog-bits-usage":
                let config = try DatadogBitsUsage.configuration(from: key)
                let url = try DatadogBitsUsage.url(for: config.site, now: now)
                data = try await get(url, headers: ["DD-API-KEY": config.apiKey,
                                                     "DD-APPLICATION-KEY": config.applicationKey], allowRedirects: false)
                return FetchResult(snapshot: try DatadogBitsUsage.parse(data, fetchedAt: now), identity: nil)
            case "fal-api-balance":
                guard key.utf8.allSatisfy({ (33...126).contains($0) }) else { throw FetchError.noKey }
                data = try await get("https://api.fal.ai/v1/account/billing?expand=credits",
                                     headers: ["Authorization": "Key \(key)"], allowRedirects: false)
                return FetchResult(snapshot: try FalBilling.parse(data, fetchedAt: now), identity: nil)
            case "sheet-113":
                let config = try MakeUsage.configuration(from: key)
                data = try await get(MakeUsage.usageURL(region: config.region, organizationID: config.organizationID),
                                     headers: ["Authorization": "Token \(config.token)"])
                return FetchResult(snapshot: try MakeUsage.parse(data, fetchedAt: now), identity: nil)
            case "sheet-81":
                data = try await get("https://elicit.com/api/v2/usage", headers: bearer(key))
                return FetchResult(snapshot: try ElicitUsage.parse(data, fetchedAt: now), identity: nil)
            case "sheet-71":
                data = try await get("https://api.poe.com/usage/current_balance", headers: bearer(key))
                return FetchResult(snapshot: try PoeBalance.parse(data, fetchedAt: now), identity: nil)
            case "sheet-121":
                data = try await post("https://api.apollo.io/api/v1/usage_stats/credit_usage_stats",
                                      headers: ["x-api-key": key, "Content-Type": "application/json", "Accept": "application/json"])
                return FetchResult(snapshot: try ApolloCredits.parse(data, fetchedAt: now), identity: nil)
            case "sheet-103":
                data = try await get("https://api.tavily.com/usage", headers: bearer(key))
                return FetchResult(snapshot: try TavilyUsage.parse(data, fetchedAt: now), identity: nil)
            case "sheet-29":
                data = try await get("https://api.v0.dev/v1/user/plan", headers: bearer(key))
                return FetchResult(snapshot: try V0Billing.parse(data, fetchedAt: now), identity: nil)
            case "copilot":
                let userData = try await get("https://api.github.com/user", headers: githubHeaders(key))
                let login = try GitHubUser.login(userData)
                data = try await get(CopilotCredits.path(login: login, now: now), headers: githubHeaders(key))
                let allowance = PlanCatalog.option(serviceID: "copilot", id: account.planID)?.monthlyCredits
                return FetchResult(snapshot: try CopilotCredits.parse(data, allowance: allowance, fetchedAt: now),
                                   identity: nil)
            case "synthesia":
                data = try await get("https://developers.synthesia.io/api/billing/credits", headers: bearer(key))
                return FetchResult(snapshot: try Synthesia.parse(data, fetchedAt: now), identity: nil)
            case "tripo":
                data = try await get("https://openapi.tripo3d.ai/v3/account/balance", headers: bearer(key))
                return FetchResult(snapshot: try Tripo.parse(data, fetchedAt: now), identity: nil)
            default:
                throw ParseError.unsupported("未対応のサービスです")
            }
        }
    }

    private static func githubHeaders(_ key: String) -> [String: String] {
        bearer(key).merging(["Accept": "application/vnd.github+json",
                             "X-GitHub-Api-Version": CopilotCredits.apiVersion]) { $1 }
    }

    private static func getUsagePage(_ url: String, headers: [String: String]) async throws -> (data: Data, link: String?) {
        var req = URLRequest(url: URL(string: url)!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpShouldSetCookies = false
        cfg.urlCache = nil
        let session = URLSession(configuration: cfg)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (data, response) = try await session.data(for: req, delegate: BlockRedirects())
            guard let response = response as? HTTPURLResponse else { throw FetchError.network }
            guard (200..<300).contains(response.statusCode) else { throw FetchError.http(response.statusCode) }
            return (data, response.value(forHTTPHeaderField: "Link"))
        } catch let error as FetchError { throw error }
        catch { throw FetchError.network }
    }

    private static func bearer(_ key: String) -> [String: String] { ["Authorization": "Bearer \(key)"] }

    private static func postJSON(_ url: String, headers: [String: String], body: Data) async throws -> Data {
        var req = URLRequest(url: URL(string: url)!, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.httpBody = body
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
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

    private static func post(_ url: String, headers: [String: String]) async throws -> Data {
        var req = URLRequest(url: URL(string: url)!, timeoutInterval: 15)
        req.httpMethod = "POST"
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
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

    private final class BlockRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    private static func get(_ url: String, headers: [String: String], allowRedirects: Bool = true, loopbackOnly: Bool = false) async throws -> Data {
        var req = URLRequest(url: URL(string: url)!, timeoutInterval: 15)
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        // Cookie・キャッシュは使わない。
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpShouldSetCookies = false
        if loopbackOnly {
            guard req.url?.host == "127.0.0.1", req.url?.scheme == "http", !allowRedirects else { throw FetchError.network }
            cfg.connectionProxyDictionary = [:]
            cfg.urlCache = nil
            cfg.urlCredentialStorage = nil
            req.cachePolicy = .reloadIgnoringLocalCacheData
        }
        do {
            let (data, res) = try await URLSession(configuration: cfg).data(for: req, delegate: allowRedirects ? nil : BlockRedirects())
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

/// 公式の Claude Code（改変なし）に `claude -p "/usage"` を実行させ、その表示を受け取る。
/// Cooltime は Claude のログイン情報に触れない。問い合わせるのは Claude Code 自身。
enum ClaudeCLI {
    static func executable() -> URL? {
        let fm = FileManager.default
        return binDirs().map { "\($0)/claude" }.first { fm.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    /// GUI アプリは、ターミナルの PATH を引き継がない。よくある置き場所を、自分で並べる。
    static func binDirs() -> [String] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        var dirs = ["\(home)/.local/bin", "\(home)/bin", "\(home)/.claude/local", "/opt/homebrew/bin",
                    "/usr/local/bin", "\(home)/.npm-global/bin", "\(home)/.bun/bin", "\(home)/.volta/bin"]
        // nvm / fnm の Node（claude が node のスクリプトのとき、node も PATH に要る）
        for base in ["\(home)/.nvm/versions/node", "\(home)/.local/share/fnm/node-versions"] {
            for v in ((try? fm.contentsOfDirectory(atPath: base)) ?? []).sorted().reversed() {
                dirs.append(base.hasSuffix("node") ? "\(base)/\(v)/bin" : "\(base)/\(v)/installation/bin")
            }
        }
        return dirs
    }

    static func usage() throws -> String {
        // セッションを履歴に残さないオプションを優先する。使えない版なら、付けずに実行する。
        let first = try run(["-p", "/usage", "--no-session-persistence"])
        if first.text.contains("%") { return first.text }
        let second = try run(["-p", "/usage"])
        if second.text.contains("%") { return second.text }
        throw FetchError.claudeFailed(detail(second, fallback: first))
    }

    private static func detail(_ r: (text: String, err: String, status: Int32), fallback f: (text: String, err: String, status: Int32)) -> String {
        let msg = [r.err, r.text, f.err, f.text].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
        let body = msg.map { String($0.prefix(120)).replacingOccurrences(of: "\n", with: " ") } ?? "出力なし"
        return "終了コード \(r.status): \(body)"
    }

    private static func run(_ args: [String]) throws -> (text: String, err: String, status: Int32) {
        let p = Process()
        let exe = executable()
        if let exe {
            p.executableURL = exe
            p.arguments = args
        } else {
            // 見つからないときは、ログインシェル（.zshrc も読む）経由で探す。
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-i", "-l", "-c", "exec claude " + args.map { "'\($0)'" }.joined(separator: " ")]
        }
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (binDirs() + (env["PATH"] ?? "/usr/bin:/bin").split(separator: ":").map(String.init)).joined(separator: ":")
        // 自分の確認で、合図のフックが動かないようにする目印。
        env["COOLTIME_USAGE_PROBE"] = "1"
        p.environment = env
        p.currentDirectoryURL = Paths.dir
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { throw FetchError.claudeNotFound }

        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: killer)
        defer { killer.cancel() }
        // 標準エラーは別スレッドで読む（どちらかが詰まって止まらないように）。
        var errData = Data()
        let errDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); errDone.signal() }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        errDone.wait()
        p.waitUntilExit()
        let r = (String(decoding: data, as: UTF8.self), String(decoding: errData, as: UTF8.self), p.terminationStatus)
        if exe == nil && r.0.isEmpty && p.terminationStatus == 127 { throw FetchError.claudeNotFound }
        return r
    }
}

