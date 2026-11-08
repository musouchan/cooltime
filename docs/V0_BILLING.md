# v0 billing integration

Cooltime reads v0's documented Platform API endpoint `GET https://api.v0.dev/v1/user/plan` when the user presses Update.

## Setup

1. Create a v0 Platform API key using the v0 account's API settings.
2. Add **v0** in Cooltime and paste the key into the API key field. Cooltime stores it in macOS Keychain.
3. Press Update to request the plan and credit balance.

The key is sent only to `api.v0.dev` as a Bearer credential. It is not stored in this repository or included in logs.

## Data

Cooltime displays the explicit `balance.remaining` value and the provided `billingCycle.end` time. It does not subtract usage from a guessed plan limit or infer a reset time if the API omits the cycle end. The API key's account identity and other user fields are not saved.

This parser has synthetic success and malformed-response tests. No v0 account or API key was available for live account verification.

## Official reference

- API endpoint and response schema: https://v0.app/docs/api/v1/reference/user/get-plan
