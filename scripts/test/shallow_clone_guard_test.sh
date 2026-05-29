#!/bin/bash
# Mac Health Keeper - shallow_clone_guard.sh の単体テスト
#
# issue: 20260529_123513_README_shallow_clone注意書き追加
#
# `scripts/lib/shallow_clone_guard.sh` の関数群（is_shallow_clone /
# warn_shallow_clone / auto_unshallow_if_requested）と直接実行モードを
# 一時 bare repo を作って BDD 形式でテストする。
#
# BDD 形式（ユースケース → シナリオ → Given/When/Then）は .agents/TEST_BDD_FORMAT.md に従う。
# 01_要件定義.md UC3-S1〜S3 + UC4-S1〜S2 に対応する。
# `make test-shell` から呼ばれ、失敗が 1 件でもあれば非 0 終了する。
# 破壊的副作用なし（mktemp で作成した一時 repo で完結）。
#
# ユースケース:
# `scripts/lib/shallow_clone_guard.sh` が、shallow clone を構造的に検出し、
# 通常 clone では警告を出さず、shallow 環境では stderr に警告 + 推奨手順を表示、
# `MACHEALTH_AUTO_UNSHALLOW=1` 指定時は `git fetch --tags --unshallow` で自動回復する。
# `version_stamp.sh` の fallback に陥る前にユーザーに気付かせることが目的。

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO_DIR/scripts/lib/shallow_clone_guard.sh"

PASS=0
FAIL=0

# --- 自前 assert ヘルパ（launchagent_lifecycle_test.sh と同流儀） ---

assert_status() {
  local expected="$1" actual="$2" msg="$3"
  if [ "$actual" -eq "$expected" ]; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (expected status $expected, got $actual)"
  fi
}

assert_eq() {
  local expected="$1" actual="$2" msg="$3"
  if [ "$actual" = "$expected" ]; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (expected '$expected', got '$actual')"
  fi
}

assert_grep() {
  local pattern="$1" text="$2" msg="$3"
  if printf '%s' "$text" | grep -qE -- "$pattern"; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (no match for /$pattern/)"
  fi
}

assert_no_match() {
  local pattern="$1" text="$2" msg="$3"
  if ! printf '%s' "$text" | grep -qE -- "$pattern"; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (unexpected match for /$pattern/)"
  fi
}

# 前提
if [ ! -f "$LIB" ]; then
  echo "FAIL: shallow_clone_guard.sh not found: $LIB" >&2
  exit 1
fi
if ! command -v git >/dev/null 2>&1; then
  echo "FAIL: git not found in PATH (tests require git)" >&2
  exit 1
fi

# --- setup / teardown ---

setup_full_repo() {
  # Given: 通常 clone を模した一時 repo（最低 1 commit + 1 tag）
  TMP="$(mktemp -d -t mac-health-scg.XXXXXX)"
  ORIGIN="$TMP/origin.git"
  FULL_REPO="$TMP/full"
  STDERR_FILE="$TMP/stderr.log"
  STDOUT_FILE="$TMP/stdout.log"
  : >"$STDERR_FILE"
  : >"$STDOUT_FILE"

  # 1) origin 用 bare repo
  git init --bare --quiet "$ORIGIN" >/dev/null 2>&1
  # 2) seed 用 worktree
  local SEED="$TMP/seed"
  git init --quiet "$SEED" >/dev/null 2>&1
  git -C "$SEED" config user.email "test@example.com"
  git -C "$SEED" config user.name "test"
  echo "hello" >"$SEED/a"
  git -C "$SEED" add a >/dev/null 2>&1
  git -C "$SEED" commit --quiet -m "c1" >/dev/null 2>&1
  git -C "$SEED" tag v0.0.1 >/dev/null 2>&1
  echo "second" >"$SEED/b"
  git -C "$SEED" add b >/dev/null 2>&1
  git -C "$SEED" commit --quiet -m "c2" >/dev/null 2>&1
  # branch 名を main に揃えて push
  local current
  current=$(git -C "$SEED" rev-parse --abbrev-ref HEAD)
  git -C "$SEED" push --quiet "$ORIGIN" "$current:refs/heads/main" >/dev/null 2>&1
  git -C "$SEED" push --quiet "$ORIGIN" --tags >/dev/null 2>&1
  # bare 側の HEAD を main に向ける（seed の HEAD が develop / master のとき clone が空になる）
  git --git-dir="$ORIGIN" symbolic-ref HEAD refs/heads/main >/dev/null 2>&1
  # 3) 通常 clone（ローカルパスでも shallow ではない）
  git clone --quiet "$ORIGIN" "$FULL_REPO" >/dev/null 2>&1
}

setup_shallow_repo() {
  setup_full_repo
  SHALLOW_REPO="$TMP/shallow"
  # shallow clone（--depth=1）。tag 履歴は来ない。
  # 注意: ローカルパスでの `git clone --depth=1` は git によって暗黙に無視される（"local clone"
  # 最適化）。実際の shallow clone を再現するには `file://` プロトコルを明示する必要がある。
  git clone --quiet --depth=1 "file://$ORIGIN" "$SHALLOW_REPO" >/dev/null 2>&1
}

teardown() {
  rm -rf "$TMP"
  unset MACHEALTH_AUTO_UNSHALLOW
}

# ===== UC3-S1: 通常 clone（非 shallow）で is_shallow_clone は 1 を返す =====

setup_full_repo
# シナリオ: 通常 git clone した repo に対して is_shallow_clone を呼ぶと「非 shallow」と判定される（01 UC3-S1）。
# Given: 通常 clone された $FULL_REPO
# shellcheck source=../lib/shallow_clone_guard.sh
source "$LIB"
# When: is_shallow_clone を呼ぶ
is_shallow_clone "$FULL_REPO"
status=$?
# Then: 戻り値 1（非 shallow）
assert_status 1 "$status" "UC3-S1: 通常 clone は is_shallow_clone=1（非 shallow）"
teardown

# ===== UC3-S1: 通常 clone を直接実行モードで呼ぶと stderr に shallow 警告が出ない =====

setup_full_repo
# シナリオ: 通常 clone に対して `bash shallow_clone_guard.sh <repo>` を直接実行すると、stderr に shallow 警告が出ず exit 0（01 UC3-S1）。
# Given: 通常 clone された $FULL_REPO
# When: 直接実行モードで guard を呼ぶ
bash "$LIB" "$FULL_REPO" >"$STDOUT_FILE" 2>"$STDERR_FILE"
status=$?
stderr_content=$(cat "$STDERR_FILE")
# Then: 終了コード 0
assert_status 0 "$status" "UC3-S1: 通常 clone で直接実行は exit 0"
# And (Then): stderr に shallow 警告が出ない
assert_no_match "shallow clone detected" "$stderr_content" "UC3-S1: 通常 clone では警告が出ない"
teardown

# ===== UC3-S2: shallow clone で is_shallow_clone は 0 を返す =====

setup_shallow_repo
# シナリオ: --depth=1 で clone した repo に対して is_shallow_clone を呼ぶと shallow と判定される（01 UC3-S2 前段）。
# Given: --depth=1 clone された $SHALLOW_REPO
# shellcheck source=../lib/shallow_clone_guard.sh
source "$LIB"
# When: is_shallow_clone を呼ぶ
is_shallow_clone "$SHALLOW_REPO"
status=$?
# Then: 戻り値 0（shallow）
assert_status 0 "$status" "UC3-S2: shallow clone は is_shallow_clone=0（shallow）"
teardown

# ===== UC3-S2: shallow clone を直接実行モードで呼ぶと stderr に警告 + 推奨手順が出る =====

setup_shallow_repo
# シナリオ: --depth=1 clone に対して直接実行すると stderr に警告と推奨手順（unshallow / AUTO 環境変数）が出る（01 UC3-S2）。
# Given: --depth=1 clone された $SHALLOW_REPO（環境変数 AUTO は未指定）
unset MACHEALTH_AUTO_UNSHALLOW
# When: 直接実行モードで guard を呼ぶ
bash "$LIB" "$SHALLOW_REPO" >"$STDOUT_FILE" 2>"$STDERR_FILE"
status=$?
stderr_content=$(cat "$STDERR_FILE")
# Then: 終了コード 0（ビルドを止めない契約）
assert_status 0 "$status" "UC3-S2: shallow clone で警告のみ・exit 0（ビルド継続）"
# And (Then): stderr に 4 種の固定メッセージが出る
assert_grep "shallow clone detected" "$stderr_content" "UC3-S2: stderr に 'shallow clone detected' が出る"
assert_grep "CFBundleVersion may fall back to 0\\.0\\.0-DEV" "$stderr_content" "UC3-S2: stderr に CFBundleVersion fallback 説明が出る"
assert_grep "git fetch --tags --unshallow" "$stderr_content" "UC3-S2: stderr に推奨手順 'git fetch --tags --unshallow' が出る"
assert_grep "MACHEALTH_AUTO_UNSHALLOW=1" "$stderr_content" "UC3-S2: stderr に AUTO 環境変数の案内が出る"
teardown

# ===== UC3-S3: MACHEALTH_AUTO_UNSHALLOW=1 で auto unshallow が走り、is_shallow_clone が false に遷移する =====

setup_shallow_repo
# シナリオ: 環境変数 MACHEALTH_AUTO_UNSHALLOW=1 を設定して直接実行すると、内部で `git fetch --tags --unshallow` が走り、その後 is_shallow_clone は false（非 shallow）になる（01 UC3-S3）。
# Given: shallow clone + AUTO=1
export MACHEALTH_AUTO_UNSHALLOW=1
# When: 直接実行モードで guard を呼ぶ
bash "$LIB" "$SHALLOW_REPO" >"$STDOUT_FILE" 2>"$STDERR_FILE"
status=$?
stderr_content=$(cat "$STDERR_FILE")
# Then: 終了コード 0
assert_status 0 "$status" "UC3-S3: AUTO=1 で auto unshallow は exit 0"
# And (Then): stderr に auto unshallow 試行ログが出る
assert_grep "MACHEALTH_AUTO_UNSHALLOW=1, attempting" "$stderr_content" "UC3-S3: stderr に auto unshallow 試行ログが出る"
assert_grep "auto unshallow succeeded" "$stderr_content" "UC3-S3: stderr に auto unshallow 成功ログが出る"
# And (Then): 実行後の repo は shallow ではない
# shellcheck source=../lib/shallow_clone_guard.sh
source "$LIB"
is_shallow_clone "$SHALLOW_REPO"
post_status=$?
assert_status 1 "$post_status" "UC3-S3: auto unshallow 後は is_shallow_clone=1（非 shallow）"
unset MACHEALTH_AUTO_UNSHALLOW
teardown

# ===== UC4-S1: 引数 0 件で usage + exit 2 =====

setup_full_repo
# シナリオ: 直接実行モードで引数 0 件にすると usage が stderr に出て exit 2 で失敗する（01 UC4-S1）。
# Given: 引数なし
# When: bash shallow_clone_guard.sh を引数 0 件で起動する
bash "$LIB" >"$STDOUT_FILE" 2>"$STDERR_FILE"
status=$?
stderr_content=$(cat "$STDERR_FILE")
# Then: 終了コード 2
assert_status 2 "$status" "UC4-S1: 引数 0 件で exit 2"
# And (Then): stderr に Usage が出る
assert_grep "Usage:" "$stderr_content" "UC4-S1: stderr に Usage が出る"
teardown

# ===== UC4-S2: .git 不在ディレクトリは「非 git」として skip + exit 0 =====

setup_full_repo
# シナリオ: .git を持たない一時ディレクトリに対して直接実行すると skip ログ + exit 0（01 UC4-S2）。
# Given: .git ディレクトリを持たない一時ディレクトリ
NON_GIT="$TMP/non_git"
mkdir -p "$NON_GIT"
# When: 直接実行モードで guard を呼ぶ
bash "$LIB" "$NON_GIT" >"$STDOUT_FILE" 2>"$STDERR_FILE"
status=$?
stderr_content=$(cat "$STDERR_FILE")
# Then: 終了コード 0
assert_status 0 "$status" "UC4-S2: .git 不在は exit 0（skip）"
# And (Then): stderr に skip ログが出る（"not a git repository"）
assert_grep "not a git repository" "$stderr_content" "UC4-S2: stderr に not a git repository ログが出る"
# And (Then): shallow 警告は出ない
assert_no_match "shallow clone detected" "$stderr_content" "UC4-S2: .git 不在では shallow 警告が出ない"
teardown

# ===== UC4-S2'（境界）: 存在しないパス渡しは「非 git」として skip + exit 0 =====

setup_full_repo
# シナリオ: 存在しないパス（typo 等）を渡したときは shallow 警告ではなく skip ログを出して exit 0 になる（境界）。
# Given: 存在しないパス
MISSING="$TMP/does_not_exist"
# When: 直接実行モードで guard を呼ぶ
bash "$LIB" "$MISSING" >"$STDOUT_FILE" 2>"$STDERR_FILE"
status=$?
stderr_content=$(cat "$STDERR_FILE")
# Then: 終了コード 0
assert_status 0 "$status" "UC4-S2': 存在しないパスは exit 0（skip）"
# And (Then): stderr に skip ログが出る
assert_grep "not a git repository" "$stderr_content" "UC4-S2': stderr に skip ログが出る"
teardown

# ===== UC3-S3 拡張: warn_shallow_clone 単体は常に 0 を返す =====

setup_shallow_repo
# シナリオ: warn_shallow_clone 関数は shallow 判定済みの前提で呼ばれ、戻り値は常に 0（ライブラリ契約）。
# Given: shallow clone repo（実体はあってもなくても警告内容に repo_dir が埋め込まれるだけ）
# shellcheck source=../lib/shallow_clone_guard.sh
source "$LIB"
# When: warn_shallow_clone を呼ぶ
warn_shallow_clone "$SHALLOW_REPO" 2>"$STDERR_FILE"
status=$?
stderr_content=$(cat "$STDERR_FILE")
# Then: 戻り値 0
assert_status 0 "$status" "UC3-S3-ext: warn_shallow_clone 単体は exit 0"
# And (Then): stderr に repo_dir が埋め込まれた警告が出る
assert_grep "shallow clone detected at $SHALLOW_REPO" "$stderr_content" "UC3-S3-ext: 警告に repo_dir が埋め込まれる"
teardown

# ===== UC3-S3 拡張 2: auto_unshallow_if_requested は AUTO 未指定なら no-op で 0 =====

setup_shallow_repo
# シナリオ: 環境変数 MACHEALTH_AUTO_UNSHALLOW が "1" 以外（未設定）のとき、auto_unshallow_if_requested は何もせず 0 を返す（スパム抑止契約）。
# Given: shallow clone repo + AUTO 未設定
unset MACHEALTH_AUTO_UNSHALLOW
# shellcheck source=../lib/shallow_clone_guard.sh
source "$LIB"
# When: auto_unshallow_if_requested を呼ぶ
auto_unshallow_if_requested "$SHALLOW_REPO" 2>"$STDERR_FILE"
status=$?
stderr_content=$(cat "$STDERR_FILE")
# Then: 戻り値 0（no-op）
assert_status 0 "$status" "UC3-S3-ext2: AUTO 未設定では auto_unshallow_if_requested は 0"
# And (Then): stderr に何も出ない（スパム抑止）
assert_eq "" "$stderr_content" "UC3-S3-ext2: AUTO 未設定では stderr は空"
teardown

# ===== UC3-S3 拡張 3: 既に full clone な repo に AUTO=1 を指定しても no-op で 0 =====

setup_full_repo
# シナリオ: 既に full clone な repo に MACHEALTH_AUTO_UNSHALLOW=1 を指定して auto_unshallow_if_requested を呼んでも、is_shallow_clone=false で短絡し 0 を返す（false-positive 回避）。
# Given: full clone + AUTO=1
export MACHEALTH_AUTO_UNSHALLOW=1
# shellcheck source=../lib/shallow_clone_guard.sh
source "$LIB"
# When: auto_unshallow_if_requested を呼ぶ
auto_unshallow_if_requested "$FULL_REPO" 2>"$STDERR_FILE"
status=$?
stderr_content=$(cat "$STDERR_FILE")
# Then: 戻り値 0
assert_status 0 "$status" "UC3-S3-ext3: full clone + AUTO=1 は no-op で 0"
# And (Then): stderr に "attempting" 行が出ない（短絡を確認）
assert_no_match "attempting" "$stderr_content" "UC3-S3-ext3: 既 full なら fetch 試行を行わない"
unset MACHEALTH_AUTO_UNSHALLOW
teardown

# ===== 直接実行・非 shallow パスは静音（stderr 空） =====

setup_full_repo
# シナリオ: 非 shallow な repo を直接実行で渡したとき、stdout/stderr ともに静音（運用ログをスパムしない契約）。
# Given: 通常 clone
unset MACHEALTH_AUTO_UNSHALLOW
# When: 直接実行モードで guard を呼ぶ
bash "$LIB" "$FULL_REPO" >"$STDOUT_FILE" 2>"$STDERR_FILE"
status=$?
stdout_content=$(cat "$STDOUT_FILE")
stderr_content=$(cat "$STDERR_FILE")
# Then: exit 0
assert_status 0 "$status" "UC3-S1-ext: 通常 clone は exit 0"
# And (Then): stderr 空
assert_eq "" "$stderr_content" "UC3-S1-ext: 通常 clone は stderr 静音"
# And (Then): stdout 空
assert_eq "" "$stdout_content" "UC3-S1-ext: 通常 clone は stdout 静音"
teardown

# --- 集計 ---
echo ""
echo "shallow_clone_guard_test: $PASS passed, $FAIL failed"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
exit 0
