#!/bin/bash
# Mac Health Keeper - version_stamp.sh の単体 smoke test
#
# issue: 20260529_105524_ビルド時バージョン自動stamp
#
# BDD 形式（ユースケース → シナリオ → Given/When/Then）は .agents/TEST_BDD_FORMAT.md に従う。
# 01_要件定義.md の UC1（install.sh による CFBundleVersion stamp）と本ファイル固有の
# 異常系（UC2: 非 git ディレクトリ fallback / UC3: 引数欠落・不正）を回帰検知する。
# `make test-shell` から呼ばれる。失敗が 1 件でもあれば非 0 終了する。
# 破壊的副作用なし（一時 plist と一時 REPO_DIR で完結し src/Info.plist は書き換えない）。

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
STAMP_SH="$REPO_DIR/scripts/lib/version_stamp.sh"
SRC_PLIST="$REPO_DIR/src/Info.plist"
PASS=0
FAIL=0

# --- 自前 assert ヘルパ（monitor_test.sh と同流儀） ---

# assert_eq <expected> <actual> <message>: 文字列一致を検証
assert_eq() {
  local expected="$1" actual="$2" msg="$3"
  if [ "$actual" = "$expected" ]; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (expected '$expected', got '$actual')"
  fi
}

# assert_nonempty <actual> <message>: 非空文字列を検証
assert_nonempty() {
  local actual="$1" msg="$2"
  if [ -n "$actual" ]; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (got empty string)"
  fi
}

# assert_grep <pattern> <text> <message>: テキスト中の正規表現一致を検証
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

# ===== UC1: install.sh による CFBundleVersion stamp（01 UC1） =====
# ユースケース: install.sh が `git describe --tags --always` の出力で
#               staged Info.plist の CFBundleVersion を上書きし、生成 .app の
#               CFBundleVersion から元 commit を逆引きできるようにする。

# シナリオ: 通常 git リポジトリで stamp すると CFBundleVersion が git describe と一致する（01 UC1-S1）。
# Given: src/Info.plist をコピーした一時 plist と、本リポジトリ（git 管理下）の REPO_DIR
tmp_plist="$TMP_DIR/Info_uc1.plist"
cp "$SRC_PLIST" "$tmp_plist"
# When: version_stamp.sh を一時 plist と REPO_DIR を引数に実行する
out=$(bash "$STAMP_SH" "$tmp_plist" "$REPO_DIR" 2>/dev/null || true)
expected=$(git -C "$REPO_DIR" describe --tags --always 2>/dev/null)
actual=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$tmp_plist" 2>/dev/null)
# Then: 一時 plist の CFBundleVersion が `git describe --tags --always` と一致する
assert_eq "$expected" "$actual" "UC1-S1: stamp 後 CFBundleVersion が git describe --tags --always と一致する"
# And (Then): stdout にも注入値が 1 行で出力される（CI ログ追跡用の契約）
assert_eq "$expected" "$out" "UC1-S1: stdout に注入値が 1 行で出力される"

# シナリオ: stamp 後の CFBundleVersion は空文字でない（最低限の健全性・01 UC1-S1 派生）。
# Given: 上記 UC1-S1 と同じ stamp 結果（actual を流用）
# When: PlistBuddy で抽出した値を使う（追加操作なし）
# Then: 空文字でない（git describe が空を返さない契約の回帰検知）
assert_nonempty "$actual" "UC1-S2: stamp 後の CFBundleVersion は空でない"

# ===== UC2: 非 git ディレクトリ REPO_DIR での fallback =====
# ユースケース: REPO_DIR が git リポジトリでない（CI のアーカイブ展開等）でも
#               version_stamp.sh はビルドを止めず、Info.plist の fallback 値を維持する。

# シナリオ: 非 git ディレクトリを REPO_DIR として渡すと fallback `0.0.0-DEV` のまま終了コード 0。
# Given: .git を持たない一時ディレクトリと、src/Info.plist のコピー（CFBundleVersion=0.0.0-DEV）
non_git="$TMP_DIR/non_git"
mkdir -p "$non_git"
tmp_plist2="$TMP_DIR/Info_uc2.plist"
cp "$SRC_PLIST" "$tmp_plist2"
# When: version_stamp.sh を非 git ディレクトリを REPO_DIR にして実行する
set +e
bash "$STAMP_SH" "$tmp_plist2" "$non_git" >/dev/null 2>&1
rc2=$?
set -e
fallback=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$tmp_plist2" 2>/dev/null)
# Then: CFBundleVersion は fallback `0.0.0-DEV` のまま維持される
assert_eq "0.0.0-DEV" "$fallback" "UC2-S1: 非 git REPO_DIR では fallback 0.0.0-DEV を維持する"
# And (Then): 終了コード 0（ビルド継続）で install.sh 経路を止めない
assert_eq "0" "$rc2" "UC2-S1: 非 git の場合でも終了コード 0（ビルド継続）"

# ===== UC3: 引数欠落・不正の異常系 =====
# ユースケース: version_stamp.sh は引数欠落・存在しない plist など不正入力に対し
#               明確な終了コードと usage / エラーメッセージで失敗し、サイレント成功しない。

# シナリオ: 引数を 1 件も渡さない場合、終了コード 2 と usage を stderr に出す（UC3-S1）。
# Given: 引数なし呼び出し
# When: bash version_stamp.sh を引数 0 件で起動する
set +e
err_out=$(bash "$STAMP_SH" 2>&1)
rc3=$?
set -e
# Then: 終了コード 2 で失敗する
assert_eq "2" "$rc3" "UC3-S1: 引数 0 件で終了コード 2"
# And (Then): usage を含むエラー出力が stderr に流れる
assert_grep "Usage:" "$err_out" "UC3-S1: usage が出力される"

# シナリオ: 第 1 引数のみで REPO_DIR 環境変数も未設定なら終了コード 2（UC3-S2）。
# Given: 第 1 引数の plist パスのみ、環境変数 REPO_DIR は unset
# When: env -u REPO_DIR bash version_stamp.sh <plist> を実行する
set +e
env -u REPO_DIR bash "$STAMP_SH" "$tmp_plist" >/dev/null 2>&1
rc4=$?
set -e
# Then: 終了コード 2（REPO_DIR を解決できないため usage 扱い）
assert_eq "2" "$rc4" "UC3-S2: REPO_DIR 未設定 + 第 2 引数なしで終了コード 2"

# シナリオ: 第 1 引数の plist が存在しない場合、終了コード 1 と plist not found エラー（UC3-S3）。
# Given: 存在しない plist パスと正常な REPO_DIR
# When: bash version_stamp.sh <missing-plist> <REPO_DIR> を実行する
set +e
err_out3=$(bash "$STAMP_SH" "$TMP_DIR/does_not_exist.plist" "$REPO_DIR" 2>&1)
rc5=$?
set -e
# Then: 終了コード 1（plist 不在の I/O エラー）
assert_eq "1" "$rc5" "UC3-S3: 存在しない plist で終了コード 1"
# And (Then): エラーメッセージに plist not found を含む（運用時の原因切り分け）
assert_grep "plist not found" "$err_out3" "UC3-S3: plist not found のエラーメッセージが出る"

# --- 集計 ---
echo ""
echo "version_stamp_test: $PASS passed, $FAIL failed"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
exit 0
