#!/bin/bash
# Mac Health Keeper - version_stamp.sh の単体 smoke test
#
# issue: 20260529_105524_ビルド時バージョン自動stamp
#
# 目的:
#   `scripts/lib/version_stamp.sh` の以下挙動を回帰検知する:
#     UC1-S1: 通常 git リポジトリで stamp すると、CFBundleVersion が
#             `git describe --tags --always` の出力と一致する。
#     UC1-S2: stamp 後の値は空文字列ではない（最低限の健全性チェック）。
#     UC2-S1: 非 git ディレクトリを REPO_DIR として渡すと、fallback `0.0.0-DEV` のまま
#             で終了コード 0（ビルド継続）になる。
#     UC3-S1: 引数を 1 件も渡さない場合、終了コード 2 と usage が stderr に出る。
#     UC3-S2: 第 2 引数を渡さず環境変数 REPO_DIR も未設定の場合も 終了コード 2。
#     UC3-S3: 第 1 引数の plist が存在しない場合 終了コード 1。
#
# 失敗が 1 件でもあれば非 0 終了する。`make test-shell` から呼ばれる。

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
STAMP_SH="$REPO_DIR/scripts/lib/version_stamp.sh"
SRC_PLIST="$REPO_DIR/src/Info.plist"
PASS=0
FAIL=0

assert_eq() {
  local expected="$1" actual="$2" msg="$3"
  if [ "$actual" = "$expected" ]; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (expected '$expected', got '$actual')"
  fi
}

assert_nonempty() {
  local actual="$1" msg="$2"
  if [ -n "$actual" ]; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (got empty string)"
  fi
}

assert_grep() {
  local pattern="$1" text="$2" msg="$3"
  if echo "$text" | grep -q -- "$pattern"; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (pattern not found: $pattern)"
  fi
}

# 前提
if [ ! -x "$STAMP_SH" ]; then
  echo "FAIL: version_stamp.sh not found or not executable: $STAMP_SH" >&2
  exit 1
fi
if [ ! -f "$SRC_PLIST" ]; then
  echo "FAIL: src/Info.plist not found: $SRC_PLIST" >&2
  exit 1
fi

# 一時ファイルクリーンアップ
TMP_DIR=$(mktemp -d -t mac-health-version-stamp.XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT

# ===== UC1: 通常 git リポジトリでの stamp =====
# シナリオ S1: stamp 後の CFBundleVersion が git describe と一致する
tmp_plist="$TMP_DIR/Info_uc1.plist"
cp "$SRC_PLIST" "$tmp_plist"
out=$(bash "$STAMP_SH" "$tmp_plist" "$REPO_DIR" 2>/dev/null || true)
expected=$(git -C "$REPO_DIR" describe --tags --always 2>/dev/null)
actual=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$tmp_plist" 2>/dev/null)
assert_eq "$expected" "$actual" "UC1-S1: stamp 後 CFBundleVersion が git describe --tags --always と一致する"
assert_eq "$expected" "$out" "UC1-S1: stdout に注入値が 1 行で出力される"
assert_nonempty "$actual" "UC1-S2: stamp 後の CFBundleVersion は空でない"

# ===== UC2: 非 git ディレクトリでの fallback =====
non_git="$TMP_DIR/non_git"
mkdir -p "$non_git"
tmp_plist2="$TMP_DIR/Info_uc2.plist"
cp "$SRC_PLIST" "$tmp_plist2"
set +e
bash "$STAMP_SH" "$tmp_plist2" "$non_git" >/dev/null 2>&1
rc2=$?
set -e
fallback=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$tmp_plist2" 2>/dev/null)
assert_eq "0.0.0-DEV" "$fallback" "UC2-S1: 非 git REPO_DIR では fallback 0.0.0-DEV を維持する"
assert_eq "0" "$rc2" "UC2-S1: 非 git の場合でも終了コード 0（ビルド継続）"

# ===== UC3: 引数欠落・不正 =====
# S1: 引数なし
set +e
err_out=$(bash "$STAMP_SH" 2>&1)
rc3=$?
set -e
assert_eq "2" "$rc3" "UC3-S1: 引数 0 件で終了コード 2"
assert_grep "Usage:" "$err_out" "UC3-S1: usage が出力される"

# S2: 第 1 引数のみ・REPO_DIR 未設定
set +e
env -u REPO_DIR bash "$STAMP_SH" "$tmp_plist" >/dev/null 2>&1
rc4=$?
set -e
assert_eq "2" "$rc4" "UC3-S2: REPO_DIR 未設定 + 第 2 引数なしで終了コード 2"

# S3: 存在しない plist
set +e
err_out3=$(bash "$STAMP_SH" "$TMP_DIR/does_not_exist.plist" "$REPO_DIR" 2>&1)
rc5=$?
set -e
assert_eq "1" "$rc5" "UC3-S3: 存在しない plist で終了コード 1"
assert_grep "plist not found" "$err_out3" "UC3-S3: plist not found のエラーメッセージが出る"

# --- 集計 ---
echo ""
echo "version_stamp_test: $PASS passed, $FAIL failed"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
exit 0
