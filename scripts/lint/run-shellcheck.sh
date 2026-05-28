#!/usr/bin/env bash
#
# scripts/lint/run-shellcheck.sh - shellcheck を対象シェルに適用
#
# 仕様（02_設計 §3.3）:
#   - shellcheck は必須ツール扱い。不在時は強い WARN を出し非 0 終了。
#   - 対象: list_shell_files の結果。
#   - shellcheck のオプションは最小限（-x で外部 source を許可、外部参照警告は抑止しない）。
#   - 終了コードは shellcheck の終了コードをそのまま返す。
#
set -u

HERE="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
# shellcheck source=scripts/lint/lib/common.sh
. "$HERE/lib/common.sh"

if ! tool_available shellcheck; then
    log_warn "shellcheck not found in PATH. shellcheck is strongly recommended."
    log_warn "  install hint: brew install shellcheck"
    exit 1
fi

# 対象ファイル一覧（空白を含むパスはこの環境では想定しない）
files="$(list_shell_files)"
if [ -z "$files" ]; then
    log_info "no shell files to check"
    exit 0
fi

log_info "shellcheck $(shellcheck --version | awk '/^version:/ {print $2}') を実行"

# 対象を IFS=\n で配列に展開（bash 3.2 互換）
old_ifs="$IFS"
IFS='
'
# shellcheck disable=SC2206
files_arr=( $files )
IFS="$old_ifs"

# 方針（02_設計 §3.3）:
#   - -x: 外部 source を追跡しようと試みる（動的パス由来の未解決は SC1091 で出るが info レベル）。
#   - --severity=warning: info 級の SC1091（動的 source の未解決）等を非 0 化しない。
#     warning 以上のみ非 0 とすることで、現状コードの誤検出ノイズを抑える。
shellcheck -x --severity=warning "${files_arr[@]}"
exit $?
