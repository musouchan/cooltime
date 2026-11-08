# Google Antigravity CLI quota integration

Cooltime can read the model quota object emitted by Antigravity CLI's documented custom statusline. This is a local, opt-in integration: it does not call an API or inspect Antigravity conversation history.

## Configure the statusline

The statusline helper requires `jq` 1.6 or newer to filter the JSON input without writing session metadata. If Homebrew is installed and `jq` is missing, install it with `brew install jq`.

1. Copy `scripts/cooltime-antigravity-statusline.sh` into `~/.gemini/antigravity-cli/` and make it executable:

   ```sh
   mkdir -p ~/.gemini/antigravity-cli
   curl -fsSL https://raw.githubusercontent.com/musouchan/cooltime/main/scripts/cooltime-antigravity-statusline.sh \
     -o ~/.gemini/antigravity-cli/cooltime-statusline.sh
   chmod 700 ~/.gemini/antigravity-cli/cooltime-statusline.sh
   ```

2. Merge the following `statusLine` object into `~/.gemini/antigravity-cli/settings.json`. Preserve your other settings:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "~/.gemini/antigravity-cli/cooltime-statusline.sh",
       "stack_with_default": true
     }
   }
   ```

3. Start or restart Antigravity CLI. Add Google Antigravity in Cooltime. The CLI invokes the statusline command when its session state changes; Cooltime rereads the local quota file.

## Data and privacy

The official statusline input includes session metadata as well as a `quota` object. The script extracts only `quota` directly from stdin with `jq` 1.6 or newer; it never writes the full input to disk. The saved file is `~/Library/Application Support/Cooltime/antigravity-quota.json`, with owner-only permissions. Cooltime reads only this file. Prompts, transcript paths, project paths, email addresses, tokens, and API keys are not stored or sent.

Quota buckets are displayed independently. A documented `remaining_fraction` becomes a used percentage; an explicit `remaining_amount` is shown as a count. `reset_time` is used only when supplied. Cooltime does not turn estimated cost or context-window usage into remaining quota. The last local value remains visible when Antigravity CLI is not running; its file modification time shows when it was last refreshed.

This uses the official CLI statusline protocol and documented quota fields. It has not been verified against a real Antigravity account in this PR.

## Sources

- Statusline scripting and JSON fields: https://antigravity.google/docs/cli/statusline
- Model quota command and refresh behavior: https://antigravity.google/docs/cli/commands/usage/
- Gemini CLI to Antigravity CLI transition: https://developers.googleblog.com/an-important-update-transitioning-gemini-cli-to-antigravity-cli/
