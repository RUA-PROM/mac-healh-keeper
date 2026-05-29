#!/bin/bash
# Mac Health Keeper - version stamp helper
#
# issue: 20260529_105524_ビルド時バージョン自動stamp
#
# 目的:
#   .app/Contents/Info.plist の CFBundleVersion キーを、git 由来の決定的な値
#   （`git -C "$REPO_DIR" describe --tags --always`）で stamp する。
#   `src/Info.plist` のリポジトリ実体は書き換えず、引数で受けた staged plist のみ更新する。
#
# 引数:
#   $1 = stamp 対象の plist パス（必須）
#   $2 または環境変数 REPO_DIR = git リポジトリのルート（必須）
#
# 終了コード:
#   0 = stamp 成功（git describe 失敗時の fallback `0.0.0-DEV` 維持も成功扱い）
#   1 = plutil 失敗 / 対象 plist が存在しない
#   2 = 引数欠落 / usage 表示
#
# 仕様:
#   - `set -euo pipefail`
#   - `git describe` は `--tags --always`（`--dirty` は付けない）。02 §3.1.3 参照。
#   - git describe が空・失敗の場合、`0.0.0-DEV`（テンプレ値）を保持して終了コード 0。
#     （ユーザー判断で fallback は `0.0.0-DEV` とする。stamp 失敗時の検知容易性を優先。）
#   - 注入した値は stdout に 1 行で出す（ログ用）。

set -euo pipefail

usage() {
  cat <<'USAGE' >&2
Usage: version_stamp.sh <staged-plist-path> [<repo-dir>]

  <staged-plist-path>  stamp 対象の Info.plist（必須・存在すること）
  <repo-dir>           git リポジトリのルート（必須。第 2 引数または環境変数 REPO_DIR）

  cwd に依存しないため、必ず REPO_DIR を渡すこと。
USAGE
}

# --- 引数解釈 ---
if [ "$#" -lt 1 ]; then
  usage
  exit 2
fi

staged_plist="$1"
repo_dir="${2:-${REPO_DIR:-}}"

if [ -z "${repo_dir:-}" ]; then
  usage
  exit 2
fi

if [ ! -f "$staged_plist" ]; then
  echo "version_stamp.sh: plist not found: $staged_plist" >&2
  exit 1
fi

# --- git describe（失敗時は 0.0.0-DEV fallback）---
# 非 git 環境 / tag 不在でも `--always` で短縮 SHA に落ちる。
# 完全に失敗（git 不在 / repo_dir に .git が無い）した場合は fallback。
derived=""
if derived_raw=$(git -C "$repo_dir" describe --tags --always 2>/dev/null); then
  derived="$derived_raw"
fi

if [ -z "$derived" ]; then
  echo "version_stamp.sh: git describe failed, keeping fallback 0.0.0-DEV (repo_dir=$repo_dir)" >&2
  derived="0.0.0-DEV"
fi

# --- plutil で CFBundleVersion を上書き ---
if ! plutil -replace CFBundleVersion -string "$derived" "$staged_plist" 2>/dev/null; then
  echo "version_stamp.sh: plutil -replace failed for $staged_plist" >&2
  exit 1
fi

# stdout にログ 1 行
echo "$derived"
exit 0
