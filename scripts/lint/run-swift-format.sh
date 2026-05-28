#!/usr/bin/env bash
#
# scripts/lint/run-swift-format.sh - swift-format による Swift lint
#
# 仕様（02_設計 §3.5）:
#   - 任意ツール扱い。swift-format 不在なら SKIP（0 終了）。
#   - `swift-format lint --strict <files>` を実行。
#   - 差分があれば非 0 終了。
#
set -u

HERE="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
# shellcheck source=scripts/lint/lib/common.sh
. "$HERE/lib/common.sh"

if ! tool_available swift-format; then
    log_skip "swift-format not found in PATH (optional). install: brew install swift-format"
    exit 0
fi

files="$(list_swift_files)"
if [ -z "$files" ]; then
    log_info "no swift files to check"
    exit 0
fi

old_ifs="$IFS"
IFS='
'
# shellcheck disable=SC2206
files_arr=( $files )
IFS="$old_ifs"

log_info "swift-format lint --strict を実行"
swift-format lint --strict "${files_arr[@]}"
exit $?
