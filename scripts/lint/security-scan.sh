#!/usr/bin/env bash
#
# scripts/lint/security-scan.sh - 秘密情報・危険パターンの静的検出
#
# 仕様（02_設計 §3.8）:
#   - 対象: list_shell_files + Sources/**/*.swift
#   - 検出パターン（grep -E、複数回）:
#       1. AWS Access Key: AKIA[0-9A-Z]{16}
#       2. password = "..." / token = "..."（リテラル）
#       3. eval <something>
#       4. rm -rf $...（unquoted 変数展開）
#       5. curl ... | sh / wget ... | sh
#   - 検出時は file:line: <pattern> を出力し非 0 終了。
#   - 末尾コメント `# noqa: security` がある行は許容（除外）。
#   - GNU grep の -P は使わず -E のみ。
#
set -u

HERE="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
# shellcheck source=scripts/lint/lib/common.sh
. "$HERE/lib/common.sh"

root="$(repo_root)"
[ -n "$root" ] || { log_error "repo root not found"; exit 1; }
cd "$root" || exit 1

# 検査対象ファイル一覧
files="$(list_shell_files)"
swift_files="$(list_swift_files)"

# 自身のスクリプト（パターン文字列を含む）は除外
exclude_paths_pattern='^scripts/lint/(security-scan\.sh|check-source-cycles\.sh|lib/common\.sh)$'

# 検査対象（自身除外）
{
    [ -n "$files" ] && printf '%s\n' "$files"
    [ -n "$swift_files" ] && printf '%s\n' "$swift_files"
} | grep -Ev "$exclude_paths_pattern" > "${TMPDIR:-/tmp}/mhk_sec_targets.$$" || true
trap 'rm -f "${TMPDIR:-/tmp}/mhk_sec_targets.$$"' EXIT
targets_file="${TMPDIR:-/tmp}/mhk_sec_targets.$$"

if [ ! -s "$targets_file" ]; then
    log_info "no files to scan"
    exit 0
fi

# パターン定義（ラベル<TAB>正規表現）
patterns="aws-access-key	AKIA[0-9A-Z]{16}
password-literal	[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd][[:space:]]*=[[:space:]]*[\"'][^\"']+[\"']
token-literal	[Tt][Oo][Kk][Ee][Nn][[:space:]]*=[[:space:]]*[\"'][^\"']+[\"']
eval-usage	(^|[^A-Za-z_])eval[[:space:]]+
rm-rf-var	rm[[:space:]]+-rf?[[:space:]]+\$
curl-pipe-sh	(curl|wget)[^|]*\\|[[:space:]]*sh($|[[:space:]])"

# 検出結果蓄積
hits_file="${TMPDIR:-/tmp}/mhk_sec_hits.$$"
: > "$hits_file"
# shellcheck disable=SC2064
trap "rm -f '$targets_file' '$hits_file'" EXIT

old_ifs="$IFS"
IFS='
'
# shellcheck disable=SC2206
target_arr=( $(cat "$targets_file") )
IFS="$old_ifs"

# パターン毎に検索
while IFS=$'\t' read -r label regex; do
    [ -z "$label" ] && continue
    # grep -n: 行番号、-E: 拡張正規表現、-H: ファイル名
    # 複数ファイルでも常にファイル名を付けるため -H を明示
    grep -nHE "$regex" "${target_arr[@]}" 2>/dev/null | \
        grep -v '# noqa: security' | \
        grep -v '// noqa: security' | \
        awk -v lab="$label" -F: '{
            printf "%s:%s: [%s] ", $1, $2, lab
            # 残りのフィールドを再連結
            out = ""
            for (i = 3; i <= NF; i++) out = out (i == 3 ? "" : ":") $i
            print out
        }' >> "$hits_file"
done <<EOF
$patterns
EOF

if [ -s "$hits_file" ]; then
    log_error "セキュリティパターンを検出しました:"
    cat "$hits_file" >&2
    exit 1
fi

log_info "セキュリティパターンの検出はありません"
exit 0
