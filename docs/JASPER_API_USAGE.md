# Jasper API usage automatic retrieval

Cooltime calls Jasper's documented workspace Usage API:

`GET https://api.jasper.ai/v1/usage?start=...&end=...&granularity=day`

Authentication uses the workspace API key in the `X-API-Key` header. The key is supplied by
the user and stored in macOS Keychain. Redirects are rejected.

Cooltime requests the seven complete UTC days before the current day and sums the returned request
buckets. Jasper documents that this endpoint covers content-generation API requests such as Run
command and Run template. It is not the Jasper web application's overall quota, credit balance, or
subscription allowance, so Cooltime does not invent any remaining balance or reset time.

Jasper Public API access is limited to Business customers. Workspace API keys can be created by
Admin or Developer roles. Live validation remains pending without such an account.

Official references:

- https://developers.jasper.ai/reference/usage-1
- https://developers.jasper.ai/docs/authentication
- https://developers.jasper.ai/docs/getting-started-1
- https://developers.jasper.ai/docs/rate-limits
