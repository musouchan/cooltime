import Foundation

/// スマホで見るための、1枚のページ（HTML）に載せる1サービス分。
public struct StatusEntry: Sendable {
    public var title: String
    public var state: QuotaState
    public var windows: [UsageWindow]
    public var credit: CreditBalance?
    public var fetchedAt: Date?
    /// 最新の取得に失敗している（数字は古い）。
    public var failed: Bool

    public init(title: String, state: QuotaState, windows: [UsageWindow], credit: CreditBalance?, fetchedAt: Date?, failed: Bool) {
        self.title = title
        self.state = state
        self.windows = windows
        self.credit = credit
        self.fetchedAt = fetchedAt
        self.failed = failed
    }
}

func htmlEscape(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
}

/// スマホで開く、動かない1枚のページ。残り・戻る時刻だけを載せる（APIキーなど、秘密は載せない）。
/// スマホでは Mac のように1分ごとに変わらないので、「○時○分の時点」を、いちばん上に大きく出す。
/// 色だけに頼らず、文字（制限中・使用可能）と棒の長さでも分かるようにする。
public func renderStatusPage(_ entries: [StatusEntry], generatedAt: Date, timeZone: TimeZone = .current) -> String {
    func clock(_ d: Date) -> String { formatClock(d, now: generatedAt, timeZone: timeZone) }

    func bar(_ w: UsageWindow) -> String {
        let label = htmlEscape(w.label)
        let reset = w.resetsAt.map { " · \(clock($0)) リセット" } ?? ""
        if let p = w.remainingPercent {
            let pct = Int(p.rounded())
            let count = w.remainingCount.map { " （残り \(Int($0.rounded()))）" } ?? ""
            let note = w.isExhausted ? "尽きた" : "残り \(pct)%"
            return """
            <div class="row"><div class="rl"><span>\(label)</span><span>\(note)\(htmlEscape(count))\(htmlEscape(reset))</span></div>\
            <div class="track" role="img" aria-label="\(label) \(note)"><div class="fill" style="width:\(max(0, min(100, pct)))%"></div></div></div>
            """
        }
        return "<div class=\"row\"><div class=\"rl\"><span>\(label)</span><span>\(htmlEscape(reset))</span></div></div>"
    }

    func card(_ e: StatusEntry, badge: String, extra: String = "") -> String {
        var body = e.windows.map(bar).joined()
        if let c = e.credit { body += "<div class=\"row\"><div class=\"rl\"><span>残高</span><span>\(htmlEscape(formatMoney(c)))</span></div></div>" }
        let stale = e.failed ? "<p class=\"warn\">取得に失敗しています。数字は古いものです。</p>" : ""
        let at = e.fetchedAt.map { "<p class=\"sub\">取得 \(clock($0))</p>" } ?? ""
        return "<section class=\"card\"><h3><span>\(htmlEscape(e.title))</span><span class=\"badge\">\(badge)</span></h3>\(extra)\(body)\(stale)\(at)</section>"
    }

    var limited: [(Date, StatusEntry)] = [], available: [StatusEntry] = [], other: [StatusEntry] = []
    for e in entries {
        switch e.state {
        case .limited(let until): limited.append((until, e))
        case .available: available.append(e)
        case .stale, .unset: other.append(e)
        }
    }
    limited.sort { $0.0 < $1.0 }

    var html = """
    <!doctype html><html lang="ja"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>Cooltime</title>
    <style>
    :root{--bg:#f2f2f7;--card:#fff;--text:#1c1c1e;--sub:#5c5c62;--track:#d8d8de;--fill:#1a5fd1;--warn:#a8320a;--line:#b8b8c0}
    @media (prefers-color-scheme:dark){:root{--bg:#000;--card:#1c1c1e;--text:#f2f2f7;--sub:#b4b4bb;--track:#3a3a3f;--fill:#6aa4ff;--warn:#ff9f80;--line:#58585f}}
    body{margin:0;padding:16px;background:var(--bg);color:var(--text);font:16px/1.5 -apple-system,"Hiragino Sans",sans-serif}
    h1{font-size:15px;margin:0 0 2px;color:var(--sub);font-weight:600}
    .asof{font-size:22px;font-weight:700;margin:0 0 16px}
    h2{font-size:14px;color:var(--sub);margin:20px 0 8px}
    .card{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:12px 14px;margin-bottom:10px}
    h3{display:flex;justify-content:space-between;align-items:center;gap:8px;font-size:17px;margin:0 0 8px}
    .badge{font-size:14px;font-weight:700;border:1.5px solid currentColor;border-radius:999px;padding:1px 10px;white-space:nowrap}
    .row{margin:8px 0}.rl{display:flex;justify-content:space-between;gap:8px;font-size:14px}
    .track{height:10px;border-radius:999px;background:var(--track);overflow:hidden;margin-top:4px}
    .fill{height:100%;background:var(--fill);border-radius:999px}
    .sub{font-size:12px;color:var(--sub);margin:6px 0 0}.warn{font-size:13px;color:var(--warn);margin:6px 0 0;font-weight:600}
    </style></head><body>
    <h1>Cooltime</h1>
    <p class="asof">\(clock(generatedAt)) 時点</p>
    <p class="sub">この画面は自動では変わりません。Mac が起きている間だけ、更新されます。</p>
    """
    if !limited.isEmpty {
        html += "<h2>制限中</h2>"
        for (until, e) in limited { html += card(e, badge: formatRemaining(until: until, now: generatedAt), extra: "<p class=\"sub\">\(clock(until)) に戻ります</p>") }
    }
    if !available.isEmpty {
        html += "<h2>使用可能</h2>"
        for e in available { html += card(e, badge: "使用可能") }
    }
    if !other.isEmpty {
        html += "<h2>確認が必要</h2>"
        for e in other { html += card(e, badge: "未確認") }
    }
    if entries.isEmpty { html += "<p>サービスがまだ登録されていません。</p>" }
    html += "</body></html>\n"
    return html
}
