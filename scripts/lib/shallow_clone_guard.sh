#!/bin/bash
# Mac Health Keeper - shallow clone guard
#
# issue: 20260529_123513_README_shallow_clone注意書き追加
#
# 目的:
#   `git clone --depth=N` / `--shallow-since` 等で shallow clone された環境を
#   検出し、stderr に警告 + 推奨手順を出力する。`scripts/lib/version_stamp.sh`
#   が `git describe --tags --always` で tag を見つけられず CFBundleVersion が
#   `0.0.0-DEV` fallback に落ちる問題を、`install.sh` 実行時点で構造的に
#   可視化することが責務。
#
# 提供 API:
#   - is_shallow_clone <repo_dir>             : 0=shallow / 1=非 shallow / 2=非 git
#   - warn_shallow_clone <repo_dir>           : stderr に警告 + 推奨手順を出す（常に 0）
#   - auto_unshallow_if_requested <repo_dir>  : MACHEALTH_AUTO_UNSHALLOW=1 で
#                                                git fetch --tags --unshallow
#                                                0=成功/不要、1=fetch 失敗
#
# 直接実行（`bash shallow_clone_guard.sh <repo_dir>`）時の挙動:
#   - 非 git           : stderr にスキップログ → exit 0
#   - shallow + AUTO=1 : auto unshallow を試行 → 成功時 exit 0、失敗時 stderr に
#                        失敗ログ + warn を残して exit 0（ビルドを止めない）
#   - shallow + AUTO=0 : warn → exit 0
#   - 非 shallow       : 静かに exit 0
#
# 設計上の判断（02 §3.2.5）:
#   - `set -u` のみ採用。`-e` は呼び出し側（`install.sh` を `source` するケース）を
#     巻き込んで止めないようにするため使わない。
#   - 終了コードは「install.sh のビルドを止めない」契約。exit 2 は引数欠落時のみ。

set -u

# usage を stderr に出して exit 2
_scg_usage() {
  cat <<'USAGE' >&2
Usage: shallow_clone_guard.sh <repo-dir>

  <repo-dir>  検査対象の git リポジトリのルート（必須）

Environment:
  MACHEALTH_AUTO_UNSHALLOW=1  shallow 検出時に `git fetch --tags --unshallow` を
                              自動実行する（既定: 無効、警告のみ）。
USAGE
}

# log_line: stderr に固定タグ付き 1 行を出す（部分一致テスト用契約）
_scg_log() {
  printf '[shallow_clone_guard] %s\n' "$*" >&2
}

# is_shallow_clone <repo_dir>
#   0 = shallow
#   1 = 非 shallow（通常 clone）
#   2 = 非 git ディレクトリ（または git コマンド不在）
is_shallow_clone() {
  local repo_dir="${1:-}"
  if [ -z "$repo_dir" ] || [ ! -d "$repo_dir" ]; then
    return 2
  fi
  # .git ディレクトリ or .git ファイル（worktree）の有無で git repo 判定
  if [ ! -e "$repo_dir/.git" ]; then
    return 2
  fi
  # git コマンドが無ければ非 git 扱い
  if ! command -v git >/dev/null 2>&1; then
    return 2
  fi

  # 優先 1: .git/shallow ファイルが存在する
  # （bare repo や worktree でも `.git` 直下に shallow が来る一般的構成）
  if [ -f "$repo_dir/.git/shallow" ]; then
    return 0
  fi

  # 優先 2: git rev-parse --is-shallow-repository
  # 出力が "true" なら shallow
  local out
  out=$(git -C "$repo_dir" rev-parse --is-shallow-repository 2>/dev/null || true)
  if [ "$out" = "true" ]; then
    return 0
  fi

  return 1
}

# warn_shallow_clone <repo_dir>
#   shallow 検出時に stderr に警告と推奨手順を出す。
#   呼び出し側で shallow 判定済みの前提だが、関数単体でも安全に動く。
#   戻り値は常に 0。
warn_shallow_clone() {
  local repo_dir="${1:-?}"
  _scg_log "WARN: shallow clone detected at $repo_dir"
  _scg_log "WARN: CFBundleVersion may fall back to 0.0.0-DEV (git describe cannot find tags)"
  _scg_log "hint: run \`git fetch --tags --unshallow\` before ./install.sh"
  _scg_log "hint: or re-run with MACHEALTH_AUTO_UNSHALLOW=1 to auto-recover"
  return 0
}

# auto_unshallow_if_requested <repo_dir>
#   MACHEALTH_AUTO_UNSHALLOW=1 のとき、`git fetch --tags --unshallow` を試行する。
#   戻り値:
#     0 = 自動回復成功 / 環境変数未設定で何もしない / shallow ではない
#     1 = fetch 失敗（呼び出し側で判断）
auto_unshallow_if_requested() {
  local repo_dir="${1:-}"
  local flag="${MACHEALTH_AUTO_UNSHALLOW:-}"
  if [ "$flag" != "1" ]; then
    return 0
  fi
  if [ -z "$repo_dir" ] || [ ! -d "$repo_dir" ]; then
    _scg_log "INFO: MACHEALTH_AUTO_UNSHALLOW=1 but repo_dir invalid: '$repo_dir' (skip)"
    return 0
  fi
  if ! command -v git >/dev/null 2>&1; then
    _scg_log "INFO: MACHEALTH_AUTO_UNSHALLOW=1 but git not found (skip)"
    return 0
  fi
  # 既に shallow でなければ何もしない
  if is_shallow_clone "$repo_dir"; then
    :
  else
    return 0
  fi
  _scg_log "INFO: MACHEALTH_AUTO_UNSHALLOW=1, attempting \`git fetch --tags --unshallow\`"
  local err
  if err=$(git -C "$repo_dir" fetch --tags --unshallow 2>&1); then
    _scg_log "INFO: auto unshallow succeeded"
    return 0
  fi
  # 失敗時の典型: 既に full clone（"--unshallow on a complete repository does not make sense"）
  # → これは success と同等に扱う（shallow ではなかった）
  if printf '%s' "$err" | grep -q "does not make sense"; then
    _scg_log "INFO: repository was already complete (no unshallow needed)"
    return 0
  fi
  _scg_log "WARN: auto unshallow failed: $err"
  return 1
}

# direct-execution entrypoint
# `bash shallow_clone_guard.sh <repo_dir>` で呼ばれたときのみ実行する。
# `source shallow_clone_guard.sh` で読み込まれたケースでは関数定義のみで終わる。
_scg_main() {
  if [ "$#" -lt 1 ]; then
    _scg_usage
    exit 2
  fi
  local repo_dir="$1"

  # shallow 判定
  is_shallow_clone "$repo_dir"
  local rc=$?
  case "$rc" in
    2)
      # 非 git ディレクトリ or .git 不在
      _scg_log "INFO: not a git repository (skip): $repo_dir"
      exit 0
      ;;
    1)
      # 非 shallow → 静かに exit 0（警告なし）
      exit 0
      ;;
    0)
      # shallow → AUTO 試行 → 失敗 or 未指定なら warn
      ;;
  esac

  if [ "${MACHEALTH_AUTO_UNSHALLOW:-}" = "1" ]; then
    if auto_unshallow_if_requested "$repo_dir"; then
      # auto 成功（or 既に full）→ 再判定して shallow でなければ warn 省略
      if ! is_shallow_clone "$repo_dir"; then
        exit 0
      fi
      # 万一まだ shallow なら念のため warn を出す
      warn_shallow_clone "$repo_dir"
      exit 0
    fi
    # 失敗時は warn にフォールバック
    warn_shallow_clone "$repo_dir"
    exit 0
  fi

  warn_shallow_clone "$repo_dir"
  exit 0
}

# source / direct exec の判定
# BASH_SOURCE[0] が $0 と一致するときは直接実行
# shellcheck disable=SC2128
if [ "${BASH_SOURCE:-$0}" = "$0" ]; then
  _scg_main "$@"
fi
