import Foundation
import AppKit
import CryptoKit
import CooltimeCore

/// アプリの中から、GitHub のリリースの新しい版に入れ替える。
/// アプリ自身がダウンロードしたファイルには「ネットから来た」目印が付かないので、
/// 毎回の警告（xattr）が要らない。確認も、ダウンロードも、「更新」ボタンを押したときだけ。
@MainActor
final class Updater: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String)
        case installing
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private let repo = "musouchan/cooltime"
    private var asset: (url: URL, sha256: String?)?

    var current: String? { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String }
    /// 開発版（swift run など）は、入れ替えできない。
    var canUpdate: Bool { current != nil && Bundle.main.bundleURL.pathExtension == "app" }

    func check() async {
        guard canUpdate, let current else { return }
        state = .checking
        do {
            var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!, timeoutInterval: 15)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.setValue("Cooltime", forHTTPHeaderField: "User-Agent")
            let cfg = URLSessionConfiguration.ephemeral
            cfg.httpShouldSetCookies = false
            let (data, res) = try await URLSession(configuration: cfg).data(for: req)
            let code = (res as? HTTPURLResponse)?.statusCode ?? 0
            switch code {
            case 200: break
            case 404: throw UpdateError.notPublic
            case 403, 429: throw UpdateError.rateLimited
            default: throw UpdateError.http(code)
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { throw UpdateError.check }
            guard AppVersion.isNewer(tag, than: current) else { state = .upToDate; return }
            let assets = json["assets"] as? [[String: Any]] ?? []
            guard let a = assets.first(where: { ($0["name"] as? String) == "Cooltime.zip" }),
                  let s = a["browser_download_url"] as? String, let url = URL(string: s) else { throw UpdateError.noAsset }
            var sha: String?
            if let d = a["digest"] as? String, d.hasPrefix("sha256:") { sha = String(d.dropFirst(7)) }
            asset = (url, sha)
            state = .available(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag)
        } catch {
            state = .failed((error as? UpdateError)?.message ?? "更新を確認できませんでした（通信を確認）")
        }
    }

    func install() async {
        guard case .available = state, let asset else { return }
        state = .installing
        do {
            try await download(asset)
        } catch {
            state = .failed((error as? UpdateError)?.message ?? "更新に失敗しました（通信を確認）")
        }
    }

    private func download(_ asset: (url: URL, sha256: String?)) async throws {
        let fm = FileManager.default
        let work = Paths.dir.appendingPathComponent("update", isDirectory: true)
        try? fm.removeItem(at: work)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)

        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpShouldSetCookies = false
        let (tmp, res) = try await URLSession(configuration: cfg).download(from: asset.url)
        guard (res as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.download }
        let zip = work.appendingPathComponent("Cooltime.zip")
        try fm.moveItem(at: tmp, to: zip)

        // GitHub が付けるハッシュと照合する（あれば）。
        if let expected = asset.sha256 {
            let digest = SHA256.hash(data: try Data(contentsOf: zip)).map { String(format: "%02x", $0) }.joined()
            guard digest == expected.lowercased() else { throw UpdateError.digest }
        }

        let unpacked = work.appendingPathComponent("new", isDirectory: true)
        try fm.createDirectory(at: unpacked, withIntermediateDirectories: true)
        try runTool("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path])
        let newApp = unpacked.appendingPathComponent("Cooltime.app")
        guard let info = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist")),
              (info["CFBundleIdentifier"] as? String) == Bundle.main.bundleIdentifier else { throw UpdateError.unexpected }

        let target = Bundle.main.bundleURL
        guard fm.isWritableFile(atPath: target.deletingLastPathComponent().path) else { throw UpdateError.notWritable }

        // 終了を待って、入れ替えて、開き直す。アプリ自身は入れ替え中のファイルを触れないので、別のシェルに任せる。
        let script = work.appendingPathComponent("swap.sh")
        let body = """
        #!/bin/sh
        pid="$1"; new="$2"; target="$3"; work="$4"
        i=0
        while kill -0 "$pid" 2>/dev/null && [ $i -lt 100 ]; do sleep 0.2; i=$((i+1)); done
        rm -rf "$target.old"
        mv "$target" "$target.old" || exit 1
        if mv "$new" "$target"; then
          /usr/bin/xattr -cr "$target" 2>/dev/null
          rm -rf "$target.old"
          /usr/bin/open "$target"
        else
          mv "$target.old" "$target"
          /usr/bin/open "$target"
        fi
        rm -rf "$work"
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "nohup /bin/sh \"$0\" \"$1\" \"$2\" \"$3\" \"$4\" >/dev/null 2>&1 &",
                       script.path, String(ProcessInfo.processInfo.processIdentifier), newApp.path, target.path, work.path]
        try p.run()
        p.waitUntilExit()
        NSApp.terminate(nil)
    }

    private func runTool(_ path: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw UpdateError.unexpected }
    }
}

enum UpdateError: Error {
    case check, noAsset, download, digest, unexpected, notWritable, notPublic, rateLimited
    case http(Int)
    var message: String {
        switch self {
        case .check: return "更新を確認できませんでした（返事を読み取れませんでした）"
        case .notPublic: return "リリースのページが見つかりません（HTTP 404）。リポジトリが非公開だと、アプリからは確認できません"
        case .rateLimited: return "短い間に確認しすぎました。しばらくしてから、もう一度押してください"
        case .http(let code): return "更新を確認できませんでした（HTTP \(code)）"
        case .noAsset: return "新しい版のファイルが見つかりません"
        case .download: return "ダウンロードに失敗しました"
        case .digest: return "ダウンロードしたファイルが一致しません。入れ替えをやめました"
        case .unexpected: return "新しい版のファイルを読み取れませんでした"
        case .notWritable: return "この場所のアプリは入れ替えできません（「アプリケーション」に移してください）"
        }
    }
}
