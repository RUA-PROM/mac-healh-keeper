#!/usr/bin/env bash
#
# scripts/lint/run-shfmt.sh - shfmt によるシェル整形差分検査
#
# 仕様（02_設計 §3.4）:
#   - 任意ツール扱い。shfmt 不在なら SKIP（0 終了）。
#   - `shfmt -d -i 4 -ci <files>` 相当（4 スペース・case インデント）。
#   - 差分があれば非 0 終了。
#
set -u

HERE="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
# shellcheck source=scripts/lint/lib/common.sh
. "$HERE/lib/common.sh"

if ! tool_available shfmt; then
    log_skip "shfmt not found in PATH (optional). install: brew install shfmt"
    exit 0
fi

files="$(list_shell_files)"
if [ -z "$files" ]; then
    log_info "no shell files to check"
    exit 0
fi

old_ifs="$IFS"
IFS='
'
# shellcheck disable=SC2206
files_arr=( $files )
IFS="$old_ifs"

log_info "shfmt $(shfmt --version 2>/dev/null) を実行（-d -i 4 -ci）"
shfmt -d -i 4 -ci "${files_arr[@]}"
exit $?
