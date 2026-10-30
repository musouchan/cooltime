#!/bin/bash
# Claude Code のステータスラインから呼ばれ、渡された JSON（利用枠を含む）を
# Cooltime が読める場所に保存する。通信はしない。
#
# 使い方（~/.claude/settings.json の statusLine.command）:
#   /path/to/cooltime-statusline.sh                    … 保存だけ
#   /path/to/cooltime-statusline.sh "既存のコマンド"    … 保存して、既存の表示も続ける
#
# 複数の Claude アカウントを使い分けるときは、環境変数 COOLTIME_SLOT でアカウントごとに
# 識別名を変える（アプリ側の「取得元の識別名」と同じにする）。既定は default。
set -u
slot="${COOLTIME_SLOT:-default}"
dir="$HOME/Library/Application Support/Cooltime"
mkdir -p "$dir"
input="$(cat)"
tmp="$(mktemp "$dir/.claude-$slot.XXXXXX")"
printf '%s' "$input" > "$tmp" && mv "$tmp" "$dir/claude-$slot.json"
if [ $# -gt 0 ] && [ -n "$1" ]; then
  printf '%s' "$input" | /bin/sh -c "$1"
fi
