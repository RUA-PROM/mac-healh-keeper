#!/bin/bash
# Mac Health Keeper - .app バンドル組み立て共通スクリプト
#
# issue: 20260529_122727_Makefile_app化拡張（D331DD8F-C57D-4869-B6FF-B46CAB8E6F60）
#
# 目的:
#   ビルド済みバイナリと Info.plist テンプレから macOS の `.app` バンドル構造
#   （Contents/MacOS/<exe>, Contents/Resources/, Contents/Info.plist）を組み立てる。
#   `Makefile::build` と `install.sh` の双方から呼び出される共通スクリプトとして
#   既存の `.app` 組み立てロジックの二重化を排除する。
#
# 使用方法:
#   build_app_bundle.sh <binary-path> <info-plist-src> <out-app-path> [<repo-dir>]
#
# 引数:
#   $1 = 実行バイナリ（必須・存在すること）
#   $2 = Info.plist テンプレ（必須・存在すること）
#   $3 = 出力 .app パス（必須・拡張子 .app）
#   $4 = git リポジトリのルート（省略可。省略時は $REPO_DIR を参照、それも空なら
#         version_stamp.sh の呼び出しを skip して fallback `0.0.0-DEV` のまま）
#
# 終了コード:
#   0 = 成功（version_stamp.sh が失敗しても `.app` 構造作成が成功していれば 0）
#   1 = 入力ファイル不在 / cp 失敗 / 拡張子チェック失敗 / mkdir 失敗
#   2 = 引数不足 / usage 表示
#
# stdout:
#   `version_stamp.sh` 経路が走った場合は注入された CFBundleVersion 値を 1 行出す。
#   stamp 経路を skip した場合（repo_dir が解決できない場合）は何も出さない。
#
# 副作用:
#   - <out.app>/Contents/{MacOS, Resources} を mkdir -p で作成（既存は保持）
#   - <binary> を <out.app>/Contents/MacOS/<binary basename> へ cp
#   - <info-plist-src> を <out.app>/Contents/Info.plist へ cp
#   - 実行ビット付与（chmod +x）
#
# 設計判断:
#   - `set -euo pipefail` を採用。version_stamp.sh は呼び出し側で warn 扱いに
#     できるよう個別に rc 判定する（02 §3.2.4 参照）。
#   - `<out.app>` が既存でも削除はしない（前回ビルドのキャッシュを残せるが、
#     必要なら呼び出し側で rm -rf してから本スクリプトを呼ぶ）。
#   - `.app` 末尾チェックは「Apple Bundle Programming Guide の慣習」を最低限担保。

set -euo pipefail

_bab_usage() {
  cat <<'USAGE' >&2
Usage: build_app_bundle.sh <binary-path> <info-plist-src> <out-app-path> [<repo-dir>]

  <binary-path>    実行バイナリ（必須・存在すること）
  <info-plist-src> Info.plist テンプレ（必須・存在すること）
  <out-app-path>   出力 .app ディレクトリ（必須・拡張子 .app）
  <repo-dir>       git ルート（省略時 $REPO_DIR 環境変数。空なら version_stamp skip）

Environment:
  REPO_DIR  $4 省略時に参照される git ルート。
USAGE
}

# --- 引数解釈 ---
if [ "$#" -lt 3 ]; then
  _bab_usage
  exit 2
fi

binary="$1"
info_plist_src="$2"
out_app="$3"
repo_dir="${4:-${REPO_DIR:-}}"

# --- 入力検証 ---
case "$out_app" in
  *.app) ;;
  *)
    echo "build_app_bundle.sh: out-app-path must end with .app: $out_app" >&2
    exit 1
    ;;
esac

if [ ! -f "$binary" ]; then
  echo "build_app_bundle.sh: binary not found: $binary" >&2
  exit 1
fi
if [ ! -f "$info_plist_src" ]; then
  echo "build_app_bundle.sh: info-plist-src not found: $info_plist_src" >&2
  exit 1
fi

# --- バンドル骨格の作成 ---
contents_dir="$out_app/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"

if ! mkdir -p "$macos_dir" "$resources_dir"; then
  echo "build_app_bundle.sh: failed to mkdir: $contents_dir" >&2
  exit 1
fi

# --- バイナリと Info.plist の配置 ---
binary_basename="$(basename "$binary")"
exe_dst="$macos_dir/$binary_basename"
plist_dst="$contents_dir/Info.plist"

if ! cp "$binary" "$exe_dst"; then
  echo "build_app_bundle.sh: failed to cp binary -> $exe_dst" >&2
  exit 1
fi
chmod +x "$exe_dst" || true

if ! cp "$info_plist_src" "$plist_dst"; then
  echo "build_app_bundle.sh: failed to cp Info.plist -> $plist_dst" >&2
  exit 1
fi

# --- CFBundleVersion を git 由来で stamp（オプション） ---
# repo_dir が空（環境変数も第 4 引数も未指定）の場合は stamp 経路を skip し、
# Info.plist テンプレの値（典型は 0.0.0-DEV）のままにする。
script_dir="$(cd "$(dirname "$0")" && pwd)"
stamp_sh="$script_dir/version_stamp.sh"

if [ -n "$repo_dir" ] && { [ -x "$stamp_sh" ] || [ -f "$stamp_sh" ]; }; then
  # version_stamp.sh は失敗しても 0.0.0-DEV fallback を維持して 0 終了する設計。
  # ここでは stdout（注入値）をそのまま本スクリプトの stdout に流す。
  if stamped=$(bash "$stamp_sh" "$plist_dst" "$repo_dir" 2>/dev/null); then
    if [ -n "$stamped" ]; then
      echo "$stamped"
    fi
  else
    # version_stamp.sh 自体が異常終了した場合は警告のみ（exit はしない）。
    echo "build_app_bundle.sh: version_stamp.sh failed (kept fallback in Info.plist)" >&2
  fi
fi

exit 0
