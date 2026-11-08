# Vertex AI モデル別トークン実績

`gcloud auth login` 済みの認証を利用し、公式 Cloud Monitoring の `aiplatform.googleapis.com/publisher/online_serving/token_count`（DELTA / INT64）を指定project・location・publisher・modelに限定して、前の完全な7 UTC日間のinput/outputトークンを取得します。全ページを取得できなければ数値を表示しません。Cloud Monitoringの値は請求残高・Gemini API/AI Studioのレート残枠ではありません。手動入力は残します。

設定欄には `project ID|location|publisher|model ID` を入力します。gcloudの既存認証と `monitoring.timeSeries.list` 権限が必要です。認証トークンは一時的にメモリで利用し、リポジトリ・設定欄に保存しません。実GCPプロジェクトでは未検証です。

公式資料: https://docs.cloud.google.com/monitoring/api/metrics_gcp_a_b 、https://docs.cloud.google.com/monitoring/api/ref_v3/rest/v3/projects.timeSeries/list
