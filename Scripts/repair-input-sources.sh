#!/usr/bin/env bash
# Ensure just the installed Wubi mode is enabled for the current user. No
# sudo, preference rewrites, app launches, input switching or agent restarts.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
apps=()
for app in "$HOME/Library/Input Methods/WubiInput.app" "/Library/Input Methods/WubiInput.app"; do
    [[ ! -d "$app" ]] || apps+=("$app")
done
if [[ ${#apps[@]} -ne 1 ]]; then
    echo '应恰好安装一份四方五笔。请先检查用户和系统的 Input Methods 目录。' >&2
    exit 1
fi
# Interpret the same implementation shipped in new apps; older installed
# helpers may destructively overwrite the input source configuration.
cat "$ROOT/Sources/WubiInput/InputSourceRegistration.swift" "$ROOT/Scripts/enable_input_source.swift" |
    /usr/bin/swift - "${apps[0]}"
echo '已确认启用四方五笔；其他输入源和当前选择未改动。'
