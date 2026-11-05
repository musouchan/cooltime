#!/bin/sh
# Antigravity CLI invokes custom statusline commands with its live session JSON on stdin.
# Persist only the documented quota object; never retain cwd, email, transcript path or session data.
set -eu
umask 077

command -v jq >/dev/null 2>&1 || exit 0
quota=$(jq -ce '.quota | select(type == "object" and length > 0)' 2>/dev/null) || exit 0
[ -n "$quota" ] || exit 0

dir="$HOME/Library/Application Support/Cooltime"
mkdir -p "$dir" 2>/dev/null || exit 0
destination="$dir/antigravity-quota.json"
temporary=$(mktemp "$dir/.antigravity-quota.XXXXXX") || exit 0
trap 'rm -f "$temporary"' EXIT HUP INT TERM
printf '%s\n' "$quota" >"$temporary" || exit 0
chmod 600 "$temporary" 2>/dev/null || exit 0
if [ -f "$destination" ] && cmp -s "$temporary" "$destination"; then
    exit 0
fi
mv -f "$temporary" "$destination" 2>/dev/null || exit 0
