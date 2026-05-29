#!/bin/bash
# Mac Health Keeper - Release artifact (.app zip) 検証スクリプト
#
# issue: 20260529_123114_CIバージョンstamp_B案実装（3D667BE0-934D-4FC6-B7D0-C423CF45B03F）
#
# 目的:
#   `make package` が生成する `build/MacHealth-<version>.zip` および同等の
#   .app zip artifact が、Release 配布の最低品質を満たしているかを検証する。
#   CI（.github/workflows/release-app.yml）からも、ローカルからも同じスクリプトで
#   呼べる単一の真実とすることで、CI と実機の検証一貫性を担保する。
#
# 使用方法:
#   release_artifact_validator.sh <zip-path> [<expected-version>] [<repo-dir>]
#
# 引数:
#   $1 = 検証対象の zip パス（必須・存在すること）
#   $2 = 期待する CFBundleVersion 値（省略可。省略時は引数 $3 / REPO_DIR から
#         `git describe --tags --always` を取得して期待値とする）
#   $3 = git リポジトリのルート（省略可。期待値解決のみに使う）
#
# 終了コード:
#   0 = 検証成功（全項目 OK）
#   1 = 検証失敗（必須キー欠落 / バイナリ不在 / CFBundleVersion 不一致 / unzip 失敗 等）
#   2 = 引数欠落 / usage 表示
#
# stdout:
#   - 検証項目ごとの OK/NG 行
#   - 末尾に "release_artifact_validator: OK" / "release_artifact_validator: NG"
#
# stderr:
#   - エラー詳細・欠落キーの一覧
#
# 設計判断:
#   - `AppBundlePolicy.requiredInfoPlistKeys`（pure-core）と同じ 6 キーを唯一の
#     必須キー集合として参照する（ハードコード重複だが、Swift から bash に
#     export する経路を増やすコストよりも保守性を優先）。AppBundlePolicy 側を
#     編集した場合は本スクリプトも同期する旨をコメントで明示。
#   - `0.0.0-DEV` の場合は WARN として扱い（shallow clone fallback の検知）、
#     終了コード 0 で完了するが stdout に WARN 行を出す。CI ではこの WARN を
#     拾って actions/warning にするか、引数 $2 を渡して厳格化する。
#   - shellcheck severity=warning に従って書く（lint-shell が緑であること）。

set -euo pipefail

usage() {
  cat <<'USAGE' >&2
Usage: release_artifact_validator.sh <zip-path> [<expected-version>] [<repo-dir>]

  <zip-path>          検証対象の .app zip（必須）
  <expected-version>  期待する CFBundleVersion 値（省略時 git describe --tags --always）
  <repo-dir>          git リポジトリのルート（expected-version 省略時の解決用）
USAGE
}

if [ "$#" -lt 1 ]; then
  usage
  exit 2
fi

zip_path="$1"
expected_version="${2:-}"
repo_dir="${3:-${REPO_DIR:-}}"

# --- 入力検証 ---
if [ ! -f "$zip_path" ]; then
  echo "release_artifact_validator: zip not found: $zip_path" >&2
  exit 1
fi

case "$zip_path" in
  *.zip) ;;
  *)
    echo "release_artifact_validator: input must be a .zip: $zip_path" >&2
    exit 1
    ;;
esac

# 必須コマンド
if ! command -v unzip >/dev/null 2>&1; then
  echo "release_artifact_validator: unzip command not found" >&2
  exit 1
fi
if ! command -v /usr/libexec/PlistBuddy >/dev/null 2>&1 && [ ! -x /usr/libexec/PlistBuddy ]; then
  echo "release_artifact_validator: /usr/libexec/PlistBuddy not found (macOS required)" >&2
  exit 1
fi

# --- 期待値解決 ---
if [ -z "$expected_version" ] && [ -n "$repo_dir" ]; then
  if [ -d "$repo_dir/.git" ] || git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1; then
    expected_version=$(git -C "$repo_dir" describe --tags --always 2>/dev/null || true)
  fi
fi

# --- 一時展開 ---
tmp_root=$(mktemp -d -t mac-health-validate.XXXXXX)
# shellcheck disable=SC2064
trap "rm -rf '$tmp_root'" EXIT

if ! unzip -q "$zip_path" -d "$tmp_root" 2>/dev/null; then
  echo "release_artifact_validator: failed to unzip: $zip_path" >&2
  exit 1
fi

# .app ディレクトリを探す（直下 1 階層のみ）
app_dir=""
for entry in "$tmp_root"/*; do
  case "$entry" in
    *.app)
      if [ -d "$entry" ]; then
        app_dir="$entry"
        break
      fi
      ;;
  esac
done

if [ -z "$app_dir" ]; then
  echo "release_artifact_validator: no *.app found at zip root: $zip_path" >&2
  exit 1
fi

ng_count=0

# 検証 1: .app 構造
info_plist="$app_dir/Contents/Info.plist"
macos_dir="$app_dir/Contents/MacOS"

if [ -f "$info_plist" ]; then
  echo "  OK   - Contents/Info.plist exists"
else
  echo "  NG   - Contents/Info.plist missing" >&2
  ng_count=$((ng_count + 1))
fi

if [ -d "$macos_dir" ]; then
  echo "  OK   - Contents/MacOS/ directory exists"
else
  echo "  NG   - Contents/MacOS/ directory missing" >&2
  ng_count=$((ng_count + 1))
fi

# 検証 2: 実行バイナリ MacHealth が存在
exe_path="$macos_dir/MacHealth"
if [ -f "$exe_path" ]; then
  echo "  OK   - Contents/MacOS/MacHealth exists"
  if [ -x "$exe_path" ]; then
    echo "  OK   - Contents/MacOS/MacHealth is executable"
  else
    echo "  NG   - Contents/MacOS/MacHealth is not executable" >&2
    ng_count=$((ng_count + 1))
  fi
else
  echo "  NG   - Contents/MacOS/MacHealth missing" >&2
  ng_count=$((ng_count + 1))
fi

# 検証 3: 必須 Info.plist キー（AppBundlePolicy.requiredInfoPlistKeys と同期）
# Sources/MacHealthKit/AppBundlePolicy.swift を編集した場合はここも同期する。
required_keys="CFBundleExecutable CFBundleIdentifier CFBundleName CFBundlePackageType CFBundleVersion CFBundleShortVersionString"
missing_keys=""
if [ -f "$info_plist" ]; then
  for key in $required_keys; do
    val=$(/usr/libexec/PlistBuddy -c "Print :$key" "$info_plist" 2>/dev/null || true)
    if [ -n "$val" ]; then
      echo "  OK   - Info.plist key '$key' = '$val'"
    else
      echo "  NG   - Info.plist key '$key' missing" >&2
      missing_keys="$missing_keys $key"
      ng_count=$((ng_count + 1))
    fi
  done
fi

if [ -n "$missing_keys" ]; then
  echo "release_artifact_validator: missing keys:$missing_keys" >&2
fi

# 検証 4: CFBundleVersion の値
actual_version=""
if [ -f "$info_plist" ]; then
  actual_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$info_plist" 2>/dev/null || true)
fi

if [ -n "$expected_version" ]; then
  if [ "$actual_version" = "$expected_version" ]; then
    echo "  OK   - CFBundleVersion matches expected ($actual_version)"
  else
    echo "  NG   - CFBundleVersion mismatch (expected='$expected_version', actual='$actual_version')" >&2
    ng_count=$((ng_count + 1))
  fi
else
  echo "  INFO - expected version not provided; skipping strict match"
fi

# 検証 5: 0.0.0-DEV fallback の検知（shallow clone 警告）
if [ "$actual_version" = "0.0.0-DEV" ]; then
  echo "  WARN - CFBundleVersion = 0.0.0-DEV (shallow clone fallback の可能性。fetch-depth: 0 を確認)" >&2
fi

# 検証 6: CFBundleExecutable と MacOS の実バイナリ名が一致
if [ -f "$info_plist" ]; then
  exe_name=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$info_plist" 2>/dev/null || true)
  if [ -n "$exe_name" ]; then
    if [ -f "$macos_dir/$exe_name" ]; then
      echo "  OK   - CFBundleExecutable '$exe_name' aligns with MacOS/$exe_name"
    else
      echo "  NG   - CFBundleExecutable '$exe_name' has no matching MacOS/$exe_name" >&2
      ng_count=$((ng_count + 1))
    fi
  fi
fi

# 集計
if [ "$ng_count" -eq 0 ]; then
  echo "release_artifact_validator: OK"
  exit 0
else
  echo "release_artifact_validator: NG ($ng_count failures)" >&2
  exit 1
fi
