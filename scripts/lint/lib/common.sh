# shellcheck shell=bash
#
# scripts/lint/lib/common.sh - lint/format/security 共通関数
#
# 役割:
#   - ログ出力（INFO / WARN / SKIP / ERROR）の統一フォーマット
#   - 必須/任意ツールの PATH 検出
#   - 対象シェルファイル/Swift ファイルの列挙
#   - リポジトリルート解決
#
# 制約:
#   - bash 3.2 互換（連想配列・mapfile・GNU 拡張は使わない）
#   - 読み取り専用（プロダクションスクリプトへの参照禁止）
#
# 02_設計 §3.2 を実装。

# 出力フォーマット ----------------------------------------------------------

# stdout に INFO を出す
log_info() {
    printf '[INFO]  %s\n' "$*"
}

# stderr に WARN を出す（終了コードは呼び出し側で判断）
log_warn() {
    printf '[WARN]  %s\n' "$*" >&2
}

# stderr に SKIP を出す（任意ツール未導入時など）
log_skip() {
    printf '[SKIP]  %s\n' "$*" >&2
}

# stderr に ERROR を出す
log_error() {
    printf '[ERROR] %s\n' "$*" >&2
}

# ツール検出 ---------------------------------------------------------------

# tool_available <name>: PATH 上にあれば 0、なければ 1。
tool_available() {
    command -v "$1" >/dev/null 2>&1
}

# require_tool <name> [<install_hint>]: 不在ならエラーを出して非 0 を返す。
require_tool() {
    local name="$1"
    local hint="${2:-}"
    if tool_available "$name"; then
        return 0
    fi
    log_error "required tool not found: $name"
    if [ -n "$hint" ]; then
        log_error "  install hint: $hint"
    fi
    return 1
}

# ルート解決 ---------------------------------------------------------------

# repo_root: リポジトリルートの絶対パスを echo。
# git があれば git rev-parse、無ければ本ファイルの位置から逆算する。
repo_root() {
    if command -v git >/dev/null 2>&1; then
        local r
        r="$(git rev-parse --show-toplevel 2>/dev/null || true)"
        if [ -n "$r" ] && [ -d "$r" ]; then
            printf '%s\n' "$r"
            return 0
        fi
    fi
    # common.sh は <repo>/scripts/lint/lib/common.sh 配置のため 3 階層上る
    local here
    here="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
    (cd "$here/../../.." >/dev/null 2>&1 && pwd)
}

# ファイル列挙 -------------------------------------------------------------

# list_shell_files: 検査対象のシェルファイルを 1 行 1 ファイルで echo。
#   対象:
#     - scripts/bin/*
#     - scripts/bin/mac-health （拡張子なし CLI）
#     - scripts/lib/*.sh
#     - scripts/config/*.sh
#     - scripts/test/*.sh
#     - install.sh / uninstall.sh
#   除外:
#     - scripts/lint/ 配下（自己参照防止）
#     - *.bats（shellcheck 対象外）
list_shell_files() {
    local root
    root="$(repo_root)"
    [ -n "$root" ] || return 1
    (
        cd "$root" || return 1
        # 拡張子 .sh のシェル
        find scripts/bin scripts/lib scripts/config scripts/test \
            -type f -name '*.sh' 2>/dev/null
        # 拡張子なし CLI（scripts/bin/mac-health）
        if [ -f scripts/bin/mac-health ]; then
            printf 'scripts/bin/mac-health\n'
        fi
        # ルート直下のインストーラ
        [ -f install.sh ] && printf 'install.sh\n'
        [ -f uninstall.sh ] && printf 'uninstall.sh\n'
    ) | sort -u
}

# list_swift_files: 検査対象の Swift ファイルを 1 行 1 ファイルで echo。
list_swift_files() {
    local root
    root="$(repo_root)"
    [ -n "$root" ] || return 1
    (
        cd "$root" || return 1
        find Sources Tests -type f -name '*.swift' 2>/dev/null | sort -u
    )
}
