# JetBrains AI Assistant local quota

JetBrains IDEs 2025.1 and later display AI Assistant's remaining monthly cloud quota in the AI widget. Cooltime reads the same IDE-produced local cache at:

\`~/Library/Application Support/{JetBrains|Google}/<IDE>/options/AIAssistantQuotaManager2.xml\`

The newest regular file is capped at 256 KiB and parsed without network access. Only \`tariffQuota\` is used for the monthly percentage; top-up quota is not mixed into it. A reset is shown only when \`nextRefill\` explicitly reports a valid date. Raw account identifiers, prompts, logs, cookies, and JetBrains credentials are not read.

The cache can be stale until the IDE refreshes its AI widget. Real subscribed-account validation remains pending.
