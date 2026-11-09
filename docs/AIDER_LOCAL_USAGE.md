# Aider のローカル利用実績

Cooltime は Aider の公式 `--analytics-log` で作成した JSONL ファイルを、ユーザーが指定したパスから読み取ります。Aider の API キーや接続先モデルの認証情報は取得しません。

```sh
aider --analytics-log "$HOME/aider-analytics.jsonl" --no-analytics
```

Cooltime で「Aider（ローカル利用実績）」を追加し、設定画面の「ローカルログのパス」にこのファイルの絶対パスを入力してください。`--no-analytics` を指定すると、Aider の解析イベントを外部送信せず、ローカルに記録できます。別の場所に保存する場合は、実際のファイルパスを指定してください。

表示するのはログ全期間の `message_send` イベントに含まれる入力トークン、出力トークン、Aider が算出した推定費用（USD）です。イベント単位の `cost` を合計し、セッション累計の `total_cost` は合計しません。接続先プロバイダーの請求額、クレジット残高、利用上限、回復時刻を示すものではありません。ログを削除・切り替えた場合は集計対象も変わります。

ログの内容は Cooltime 内で読み取り、イベントの文章やユーザー識別子は保存しません。大きすぎるファイル、壊れた JSONL、必要な使用量フィールドのないログはエラーにします。実アカウントでの照合は未完了です。

公式資料: [Aider Analytics](https://aider.chat/docs/more/analytics.html)、[公式サンプルログ](https://github.com/Aider-AI/aider/blob/main/aider/website/assets/sample-analytics.jsonl)。
