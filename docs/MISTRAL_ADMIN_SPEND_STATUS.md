# Mistral Enterprise 月間上限状態

公式 Enterprise Admin API の `GET /v1/admin/spend-limit` が明示する `limits.completion.monthly_limit_reached` を表示します。上限到達の真偽だけを示し、残額・利用量・回復日時は推定しません。一般 API key では使えず、Enterprise 契約と専用 Admin API key が必要です。キーは既存の Keychain に保存し、手動入力も残します。

実アカウント検証は未実施です。公式資料: https://docs.mistral.ai/admin/admin-api/usage-metrics および https://docs.mistral.ai/api/endpoint/beta/admin/billing
