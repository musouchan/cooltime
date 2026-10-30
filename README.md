# Cooltime

AI・API・MCP の利用制限が「あと何分・何時間で戻るか」を、メニューバーに出す個人用の macOS アプリです。
稼働状況の監視アプリではありません。**戻る時刻を正確に取れたものだけ**を載せます。

> **状態: 最初の骨組みです。まだ一度もビルドしていません。** この環境に Swift/Xcode がなかったため、
> コードは書いただけで、コンパイルもテストも実行していません。最初の作業は `swift build` と `swift test` です。

## 動かし方

必要なもの: macOS 14 以降、Xcode 15 以降（または Swift 5.9 以降）。

```bash
swift test          # 中身（状態の判定・時間の表示・各社の解析）のテスト
swift run Cooltime
```

Dock にアイコンは出ません（メニューバーだけ）。直接配布を想定しています。
`~/.codex` の読み取りと `codex` コマンドの起動にはサンドボックスの外が必要なため、App Store 配布には向きません。

## 最初の状態

何も追加されていません。メニューバーのアイコン →「管理…」→ ＋ で、使っているサービスだけ選びます。
選ぶまで、通信も取得もしません。

## 載せるサービスと取得方法

| サービス | 取得方法 | 必要なもの |
|---|---|---|
| Anthropic（Claude・Claude Code） | Claude Code のステータスライン（公式） | 下の設定。Pro／Max 契約のみ（Team は対象外） |
| OpenAI（Work・Codex） | `codex app-server`（公式機能） | `codex` コマンドとログイン |
| ElevenLabs | 公式API | APIキー |
| Firecrawl | 公式API | APIキー |
| Vercel AI Gateway | 公式API（クレジット残高） | APIキー |
| OpenRouter | 公式API（残額） | APIキー（上限を設定したもの） |
| DeepSeek | 公式API（残高） | APIキー |

**載せないもの**: Figma MCP、Claude Code（API課金）、Lovable、Netlify、Vercel Hobby、Midjourney、
クラウド側のコネクタ、Anthropic API・OpenAI API のレート制限。戻る時刻を正確に取る方法が確認できていないためです。

## Claude Code の設定（Anthropic の枠を読むために）

アプリは Claude Code の設定を書き換えません。自分で次を設定します。

```bash
chmod +x scripts/statusline-tee.sh
```

`~/.claude/settings.json` の `statusLine` に、このスクリプトを指定します。
すでにステータスラインを使っている場合は、元のコマンドを引数に渡すと、そのまま動き続けます。

```json
{
  "statusLine": {
    "type": "command",
    "command": "/絶対パス/scripts/statusline-tee.sh ~/.claude/my-statusline.sh"
  }
}
```

保存されるのは `rate_limits`（枠の使用%と戻る時刻）だけです。会話の内容やパスは保存しません。
保存先: `~/Library/Application Support/Cooltime/claude-statusline.json`

Claude Code で1回メッセージを送ると、情報が書き出されます。

## あとから取得方法を足せるようにしてあります

いまは公式の方法だけです。Cookie・ウェブセッションなどの非公式な方法は**入っていません**。
ただし、あとから足せる作りにしてあります（`Sources/RecoveryCore/Source.swift`）。

1. `UsageSource` に従う型を作る
2. `SourceKind` に case を足す
3. `SourceRegistry.standard` に登録する
4. `Catalog` に、そのサービスを `tier: .experimental` で足す

画面や状態の判定は変えなくて大丈夫です。非公式なもの（`.experimental`）は次のように扱われます。

- 管理 → 設定の「実験的な取得を使う」が**オフのままだと、追加メニューにも出ず、取得もしません**（既定はオフ）。
- オンにするときは、規約に反する可能性や、予告なく止まる可能性を示す確認画面を出します。
- 追加メニューでは「（実験的）」と表示します。
- 認証情報は Keychain にだけ保存します。

## 取得のルール

- **自動で通信しない。** 手元のファイル（ステータスライン）の読み直しは30秒ごとに自動ですが、
  各社のAPIと Codex への問い合わせは、利用者が更新ボタンを押したときだけです。
- **APIキーは Keychain だけ。** ファイル・ログ・画面には出しません。
- **数字を作らない。** 戻る時刻が取れない枠は載せません。想定と違う応答はエラーにします。
- **時間が過ぎても「戻った」とは決めない。** 目安を過ぎたら「リセット目安です。必要なら再確認してください」と出し、
  再取得するまで使用可能にはしません。
- 時刻の表示は端末のタイムゾーンです。

## 画面

- メニューバー: 一番早く戻るものの「あと43分」。制限中が無いときと、目安を過ぎたときは、アプリのアイコンだけ。
- ポップオーバー: 制限中 / 使用可能 / クレジット。クレジットは ⟳（残高を更新）と ＋（支払いページを開く）。
- 管理: アカウント名、個人／法人、プラン、支払いページのURL、APIキー。
  支払いページは既定のブラウザで開くだけで、アプリの中ではログインも支払いもしません。

## 実機で確認が必要なこと

1. **Codex の `account/rateLimits/read`** の応答の項目名（`CodexSource.parse` は想定で書いています）。
2. **既定の支払いページのURL**（`Catalog.swift`）。各社のページで確認してください。
3. **OpenRouter** は残額の上限を設定したキーでないと残額が返りません。
4. **MenuBarExtra のラベル**に枠線（カプセル）が付くか。付かない場合は NSStatusItem に切り替えます。
5. Anthropic の枠は、Claude Code で最初に応答があるまで空です。

## まだ入っていないもの

- 通知（戻る時刻の通知）。SwiftPM の実行ファイルでは通知センターが使えないため、Xcode のアプリターゲットにしてから。
- 登録した他のブラウザを選ぶ画面（`browserBundleID` の項目だけあります）。
- Cursor（非公式API）、v0（単位の確認後）。
- 複数端末での共有（v1 では対応しません）。
