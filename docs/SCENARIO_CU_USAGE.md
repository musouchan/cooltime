# Scenario Creative Units automatic retrieval

Cooltime uses Scenario's documented team limits endpoint:

- `GET https://api.cloud.scenario.com/v1/teams/{teamId}/limits`
- HTTP Basic authentication with the Scenario API key and API secret
- configuration stored in macOS Keychain as `teamId|apiKey|apiSecret`

The response supplies the current billing period, plan Creative Units limit, current
Creative Units value, and each one-shot CU purchase's direct remaining value. Cooltime:

- shows the exact current-period used CU reported by Scenario;
- computes the plan remaining count only as `limits.creativeUnits - values.creativeUnits`;
- shows the sum of direct `oneShotCreativeUnits[].remaining` values separately;
- uses the official period end as the reset time;
- never invents a monthly allowance, balance, or reset time.

Redirects are blocked. The Team ID is restricted to a path-safe identifier and credentials
are never written to repository files or logs.

Official references:

- https://docs.scenario.com/api/typescript/resources/teams/methods/retrieve_limits
- https://docs.scenario.com/get-started/documentation/key-concepts-terminology/api-key-and-authentication
- https://docs.scenario.com/get-started/documentation/provisioning-per-user-api-keys

Live validation still requires a Scenario team ID and API credentials with the documented
read access. Until then, the existing manual `sheet-174` entry remains available.
