# Cooltime

AI・API・MCP の**利用制限が「あと何分・何時間で戻るか」**を、Mac のメニューバーで確認するアプリです。
稼働状況の監視ではなく、「使い切った後、いつ戻るか」を知るためのものです。

- メニューバーには、一番早く戻るもの 1 件だけを「あと43分」の形で出します（カプセルで他のアイコンと区別）。
- クリックすると、**制限中 / 使用可能 / クレジット** の一覧が開きます。
- 「管理…」から、使っているサービスだけを自分で追加します。追加するまで何も取得・通信しません。
- macOS 14 以降。Dock にアイコンは出ません。

## インストール

1. [Releases](../../releases) から `Cooltime.zip` をダウンロードして展開します。
2. `Cooltime.app` を「アプリケーション」に移します。
3. 署名・公証をしていない個人配布のため、初回は **右クリック →「開く」** で起動してください。
   （「壊れている」と出る場合は、ターミナルで `xattr -dr com.apple.quarantine /Applications/Cooltime.app`）

## 取得できるサービス

| サービス | 取得方法 | 通信 |
|---|---|---|
| Claude / Claude Code（Pro・Max） | Claude Code のステータスラインが渡す利用枠（5時間・週） | なし（ファイルを自動で読み直す） |
| ChatGPT / Codex | `codex app-server` への問い合わせ（5時間・週、クレジット） | 更新ボタンのときだけ |
| ElevenLabs | 公式 API（月の文字数・次のリセット） | 更新ボタンのときだけ |
| Firecrawl | 公式 API（月のクレジット・請求期間の終了） | 更新ボタンのときだけ |
| Vercel AI Gateway / OpenRouter / DeepSeek | 公式 API（残高。OpenRouter は上限付きキーのみ） | 更新ボタンのときだけ |

戻る時刻を正確に取れないもの（Figma MCP、API 課金の Claude Code、Lovable、Netlify、Midjourney、
Anthropic / OpenAI API のレート制限など）は載せていません。推定の数字も出しません。
v0・Cursor は検証待ちのため、今回は入れていません。

## Claude / Claude Code を使う設定（自分で行います）

Cooltime は他のツールの設定を書き換えません。次を自分で設定してください。

1. `scripts/cooltime-statusline.sh`（アプリ内の `Cooltime.app/Contents/Resources/` にも入っています）を好きな場所に置き、実行権限を付けます。
2. `~/.claude/settings.json` に追加します。

```json
{
  "statusLine": { "type": "command", "command": "/path/to/cooltime-statusline.sh" }
}
```

すでにステータスラインがある場合は、そのコマンドを引数にすると、保存したうえで表示も続きます。

```json
{
  "statusLine": { "type": "command", "command": "/path/to/cooltime-statusline.sh 'いまのコマンド'" }
}
```

Claude のアカウントが複数あるときは、アカウントごとに環境変数 `COOLTIME_SLOT`（例: `work`）を変え、
管理画面の「取得元の識別名」に同じ名前を入れます。

## 守っていること

- 戻り時刻は**公式の値だけ**を使います。目安を過ぎても「戻った」とは決めず、「リセット目安です。必要なら再確認してください」と出します。
- APIキーは **Keychain にだけ**保存します（ファイル・ログ・画面には出しません）。
- 通信先は各サービスの公式の窓口だけです。分析用の送信はしません。データは Mac の中（`~/Library/Application Support/Cooltime/`）にだけ保存します。
- アプリの中でログインや支払いはしません。支払いは、支払いページを既定のブラウザで開くだけです。
- 画面の読み取り・Cookie・スクレイピングなど、規約に反しかねない方法は使っていません。
- 時刻は常にこの Mac のタイムゾーン。動きは最小限で、くるくる回る表示はありません。

## 実機で確認が必要なところ

作成環境が Mac ではなかったため、次は未確認です。動かして、ずれていたら教えてください。

- Claude Code のステータスラインの JSON 項目名（`rate_limits.five_hour.used_percentage` / `resets_at`）。
- Codex の `account/rateLimits/read` の応答の項目名と、起動方法（ログインシェル経由で `codex app-server`）。
- 各 API の応答の項目名（テストは公式ドキュメントの形を元にしています）。
- メニューバーのカプセル表示の見え方（ライト／ダーク）。

## 開発

```bash
swift test                 # 時計を差し替えるテスト（時刻の計算・状態の判定・応答の読み取り）
scripts/build-app.sh       # build/Cooltime.app と build/Cooltime.zip を作る
```

構成: `Sources/CooltimeCore`（画面に依存しない計算・読み取り）と `Sources/Cooltime`（SwiftUI アプリ）。
サービスの追加は `Catalog.swift` と、`Parsers.swift` / `Fetchers.swift` に足します。
非公式な取得方法を足す場合は、既定オフの「実験的」として、確認画面つきで追加する前提です（今回は仕組みのみで、実装は入れていません）。

## リリース

`v0.1.0` のようなタグを push すると、GitHub Actions が Mac 上でテスト・ビルドし、Releases に `Cooltime.zip` を添付します。
