# OpenCode Go through the official local server

This integration requires OpenCode V2 already running and signed in to the intended Console workspace, with a Go entitlement. It reads the documented experimental local HTTP API, not the private Console endpoints used internally by OpenCode. It never launches a service, changes its configuration, starts a model session or reads its credential files.

Add OpenCode Go（ローカル利用枠）. In the Keychain-backed field enter `port|workspace-id|local-server-password`. Find the actual local port with `opencode service status`. Other HTTP clients use Basic authentication with the fixed username `opencode`; provide an existing local password or a supported pairing-session password. This is not the Console API key. The expected workspace ID must match the response before any data is accepted. The server's default location is used; projects connected to another workspace require a separately configured server/default location.

Only `http://127.0.0.1` and a user-selected port in 1024–65535 are accepted. Redirects, cookies, caches and system proxies are disabled for this connection. The packaged app has an ATS HTTP exception for 127.0.0.1 only. There is no general insecure-network exception.

The official `UsageLimits.Meter.percent` is the **used** percentage. `resetsAt` is milliseconds since Unix epoch. Display rolling, weekly and monthly Go windows. A `limited` flag is shown as 制限中, even if the rounded percentage is below 100. Signed-out/null, missing Go, mismatched workspace, malformed values and expired resets produce an error, never an invented allowance. Console budget definitions can overlap and are intentionally not summed or displayed in this first Go integration. Existing manual OpenCode entries remain available.

Synthetic schema and configuration tests are provided. A real OpenCode V2 server, Go contract, authenticated responses and Mac UI comparison remain unverified. Verify all three windows against the same workspace in the official UI; test a wrong password/workspace, stopped server, signed-out account and expired response. The endpoint is experimental and may change between V2 releases.

Sources checked 2026-11-06:
- https://dev.opencode.ai/v2/docs/api
- https://dev.opencode.ai/v2/docs/cli/web
- https://dev.opencode.ai/v2/openapi.json
- https://github.com/anomalyco/opencode/blob/866fb262bacd955dd26ee72331f18136e5575e98/packages/schema/src/usage-limits.ts
