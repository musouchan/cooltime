# Cooltime

AI・API・MCP の**利用制限が「あと何分・何時間で戻るか」**を、Mac のメニューバーで確認するアプリです。
稼働状況の監視ではなく、「使い切った後、いつ戻るか」を知るためのものです。

- メニューバーには、一番早く戻るもの 1 件だけを「あと43分」の形で出します（カプセルで他のアイコンと区別）。
- クリックすると、**制限中 / 使用可能 / クレジット** の一覧が開きます。
- **起動すると、この Mac でログイン済みの Claude Code と Codex を自動で見つけて追加します**（メールアドレス・プランも自動で入ります）。
  自分で削除したものは、戻しません。APIキー系のサービスだけは、「管理…」から自分で追加します。
- macOS 14 以降。Dock にアイコンは出ません。

## インストール

1. [Releases](../../releases) から `Cooltime.zip` をダウンロードして展開します。
2. `Cooltime.app` を「アプリケーション」に移します。
3. 署名・公証をしていない個人配布のため、初回は macOS に止められます（マルウェアが見つかったという意味ではありません）。
   「ゴミ箱に入れる」は押さず、「完了」で閉じてから、次のどちらかで開きます。
   - 「システム設定」→「プライバシーとセキュリティ」→ 下の方の「"Cooltime" は開くことがブロックされました」の「このまま開く」
   - ターミナルで `xattr -dr com.apple.quarantine /Applications/Cooltime.app` を実行してから、もう一度開く

   macOS 14 以前は、右クリック →「開く」でも開けます。

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

## Claude Code との連携（ボタン1つ）

Claude の残り時間は、Claude Code のステータスラインから取ります。そのために `~/.claude/settings.json` へ記録の設定を足します。

1. 「管理…」→ Claude を選び →「設定する…」を押します。
2. **変更前と変更後の内容が表示される**ので、確認して「設定する」を押します。
3. 元のファイルは `settings.json.cooltime-backup-…` として残ります。すでにステータスラインがある場合は、壊さずに、そのまま表示も続きます。「元に戻す」でいつでも外せます。

設定のあと、Claude Code を使うと、利用枠が Cooltime に出ます。
Claude のアカウントが複数あるときは、アカウントごとに環境変数 `COOLTIME_SLOT`（例: `work`）を変え、
管理画面の「取得元の識別名」に同じ名前を入れます。

## 守っていること

- 戻り時刻は**公式の値だけ**を使います。目安を過ぎても「戻った」とは決めず、「リセット目安です。必要なら再確認してください」と出します。
- APIキーは **Keychain にだけ**保存します（ファイル・ログ・画面には出しません）。
- 自動検出は、ファイルがあるかを見るだけです（通信なし）。読むのは、メールアドレス・プラン名だけで、トークンやパスワードは読みません。
  通信するのは、Codex の初回の1回と、更新ボタンのときだけです。
- 他のツールの設定（Claude Code の settings.json）は、内容を見せて同意を得たときだけ、バックアップを取って書き換えます。
- 通信先は各サービスの公式の窓口だけです。分析用の送信はしません。データは Mac の中（`~/Library/Application Support/Cooltime/`）にだけ保存します。
- アプリの中でログインや支払いはしません。支払いは、支払いページを既定のブラウザで開くだけです。
- 画面の読み取り・Cookie・スクレイピングなど、規約に反しかねない方法は使っていません。
- 時刻は常にこの Mac のタイムゾーン。動きは最小限で、くるくる回る表示はありません。

## 実機で確認が必要なところ

作成環境が Mac ではなかったため、次は未確認です。動かして、ずれていたら教えてください。

- Claude Code のステータスラインの JSON 項目名と、`~/.claude.json` の `oauthAccount.emailAddress`（`rate_limits.five_hour.used_percentage` / `resets_at`）。
- Codex の `account/rateLimits/read`・`account/read` の応答の項目名と、起動方法（ログインシェル経由で `codex app-server`）。
- 各 API の応答の項目名（テストは公式ドキュメントの形を元にしています）。
- メニューバーのカプセル表示の見え方（ライト／ダーク）。

## 開発

```bash
swift test                 # 時計を差し替えるテスト（時刻の計算・状態の判定・応答の読み取り・設定ファイルの書き換え）
scripts/build-app.sh       # build/Cooltime.app と build/Cooltime.zip を作る
```

構成: `Sources/CooltimeCore`（画面に依存しない計算・読み取り）と `Sources/Cooltime`（SwiftUI アプリ）。
サービスの追加は `Catalog.swift` と、`Parsers.swift` / `Fetchers.swift` に足します。
非公式な取得方法を足す場合は、既定オフの「実験的」として、確認画面つきで追加する前提です（今回は仕組みのみで、実装は入れていません）。

## リリース

`v0.1.0` のようなタグを push すると、GitHub Actions が Mac 上でテスト・ビルドし、Releases に `Cooltime.zip` を添付します。
