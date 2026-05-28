#!/usr/bin/env bash
#
# scripts/lint/run-swiftlint.sh - swiftlint による Swift lint
#
# 仕様（02_設計 §3.6）:
#   - 任意ツール扱い。swiftlint 不在なら SKIP（0 終了）。
#   - `swiftlint --strict` を実行（設定ファイル無しでも default rules で動作）。
#
set -u

HERE="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
# shellcheck source=scripts/lint/lib/common.sh
. "$HERE/lib/common.sh"

if ! tool_available swiftlint; then
    log_skip "swiftlint not found in PATH (optional). install: brew install swiftlint"
    exit 0
fi

root="$(repo_root)"
cd "$root" || exit 1

log_info "swiftlint --strict を実行"
swiftlint --strict
exit $?
