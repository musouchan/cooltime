# Zendesk AI Agents - Advanced 日次利用実績

公式 Data Export API が前 UTC 日に確定した会話ファイルから、指定 bot の `resolution_tier = core_resolution` かつ `test_mode = false` を数えます。これは**前日の確認済み解決件数**であり、契約枠の残数・請求額・回復時刻ではありません。従来の手動入力も残ります。

1. Zendesk AI Agents - Advanced の管理者が組織 ID、bot ID、組織 API トークンを取得します。
2. Cooltime で「Zendesk AI Agents（確認済み解決）」を追加し、キー欄に `subdomain|organization ID|bot ID|API token` を入力します。キーは既存 Keychain にだけ保存されます。
3. 更新時、公式 API に前 UTC 日の日付を POST し、署名 URL のホストを検証して Google Cloud Storage の JSON を一時的に読み込みます。会話テキストや顧客情報は保存しません。

複数ファイルの重複会話、想定外ホスト、スキーマ変更、10 MB を超えるファイルでは取得エラーを表示し、不完全な件数を採用しません。前日分のエクスポートがまだ提供されない場合もエラーです。集計単位は bot ごと・前 UTC 日のみで、組織全体の請求集計とは一致しない場合があります。実アカウントでの検証は未実施です。

公式資料: https://developer.zendesk.com/documentation/ai-agents/getting-started/data-export/ 、https://support.zendesk.com/hc/en-us/articles/9570369117338-About-automated-resolution-tiers
