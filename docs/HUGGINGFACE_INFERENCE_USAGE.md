# Hugging Face organization inference usage

Add Hugging Face（組織推論実績） and store `organization-slug|billing-read-token` in the existing Keychain field. The endpoint is available to qualifying Enterprise organizations (the official OpenAPI also badges Enterprise Plus and Academia Hub). Personal compute balance and custom provider-key billing are not covered.

GET `/api/organizations/{name}/billing/usage/inference` returns daily periods with member/model/provider usage, `requestCount` and `costCents`. Cooltime sums reported cents and requests for seven completed UTC days, allowing two hours for reporting lag. It keeps the API's cents unit; rows are rounded and their sum may differ from the invoice. It never subtracts this from the shared compute credits or infers a reset time. Other HF compute products are excluded.

The requested seven days fit within `limit=31` daily periods. The initial implementation rejects any unexpected nonempty Link pagination header instead of displaying a partial total or following an untrusted URL. It also rejects invalid or repeated periods, duplicate grains and invalid amounts. An explicit returned day with no rows reports zero; a completely empty response remains unknown. Other-user metadata is discarded and not saved.

Official OpenAPI JSON was retrieved directly on 2026-11-06 via the URL used by Hugging Face's own OpenAPI viewer. Tests use synthetic fixtures matching its types. API token access, actual response headers and Mac UI comparison remain unverified. Verify one organization's same UTC days, rounded cents and request counts using the billing report; check permission errors and paging behavior before claiming live support.

Sources:
- https://huggingface.co/docs/inference-providers/pricing
- https://huggingface.co/.well-known/openapi.json
- https://huggingface.co/spaces/huggingface/openapi/blob/main/app.ts
