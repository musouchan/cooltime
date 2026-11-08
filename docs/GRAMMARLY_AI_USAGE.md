# Grammarly organization AI usage

Eligible administrators on Grammarly Enterprise or Grammarly for Education institution-wide can create OAuth credentials with `analytics-api:read`. Enter the numeric Grammarly user ID, client ID and client secret, separated by pipes, in the Keychain-backed field. The documented Analytics API response identifies users by numeric ID.

Cooltime requests a client-credentials token from the official OAuth host and reads the official paginated analytics endpoint. It displays the selected user's reported prompt count for seven UTC days with a 48-hour reporting buffer. The API reads pages for the organization. Cooltime discards other users' values and does not store names, email addresses, raw records or the access token. Missing data, invalid counts and incomplete pagination fail without replacing the prior result. The original manual entry remains available.

Synthetic tests cover successful and empty usage, OAuth inputs, malformed responses and pagination. Live OAuth scope, user ID selection, usage comparison and Mac UI are unverified. Compare the same user and dates in the authorized organization's reports before relying on the result.

- https://developer.grammarly.com/analytics-api.html
- https://developer.grammarly.com/oauth-credentials.html
- https://developer.grammarly.com/your-first-api-request.html
