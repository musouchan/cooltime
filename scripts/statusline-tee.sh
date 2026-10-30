#!/bin/bash
# Claude Code のステータスラインの入力から、利用枠の情報（rate_limits）だけを保存する。
# すでにステータスラインを使っている場合は、元のコマンドを引数に渡すと、そのまま動き続ける。
#
#   例) "statusLine": { "type": "command", "command": "/path/to/statusline-tee.sh ~/.claude/my-statusline.sh" }
#
# 保存先: ~/Library/Application Support/Cooltime/claude-statusline.json
# 保存するのは rate_limits だけ。会話の内容やパスなどは保存しない。

dir="$HOME/Library/Application Support/Cooltime"
mkdir -p "$dir"
input="$(cat)"

tmp="$dir/claude-statusline.json.tmp"
if printf '%s' "$input" | /usr/bin/plutil -extract rate_limits json -o - - > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
  mv "$tmp" "$dir/claude-statusline.json"
else
  rm -f "$tmp"
fi

if [ "$#" -gt 0 ]; then
  printf '%s' "$input" | "$@"
fi
