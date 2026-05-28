#!/bin/bash
# Mac Health Keeper - ログローテート（log.sh / lock.sh）の単体テスト（bats 不在時の自前 assert ランナー）
#
# log_rotate.bats と同一 source・同一前提で UC1-S1/UC1-S2/UC2-S1/UC3-S1/UC4-S1 + finalize_job 冪等 +
# A 回帰（should_notify）を再現する。bats が無い環境（01 §3.4 / 02 §3.3 のフォールバック）で
# `make test-shell` から呼ばれる。失敗が 1 件でもあれば非 0 終了する。
# すべて一時 LOG_DIR・固定入力で破壊的副作用なし（$HOME/Library/Logs/MacHealth を汚さない）。
#
# BDD 形式（ユースケース → シナリオ → Given/When/Then）は .agents/TEST_BDD_FORMAT.md に従う。
# ユースケース: 追記ログをサイズ世代でローテートし、out/err も対象化し、並行更新を直列化し、失敗を可視化する。

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0

# --- 自前 assert ヘルパ（monitor_test.sh と同流儀） ---

# assert_status <expected> <actual> <message>: 終了コード一致を検証
assert_status() {
  local expected="$1" actual="$2" msg="$3"
  if [ "$actual" -eq "$expected" ]; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (expected status $expected, got $actual)"
  fi
}

# assert_le <value> <limit> <message>: value <= limit を検証
assert_le() {
  local value="$1" limit="$2" msg="$3"
  if [ "$value" -le "$limit" ]; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (expected <= $limit, got $value)"
  fi
}

# assert_eq <expected> <actual> <message>: 値一致を検証
assert_eq() {
  local expected="$1" actual="$2" msg="$3"
  if [ "$actual" = "$expected" ]; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (expected '$expected', got '$actual')"
  fi
}

# assert_file <path> <message>: ファイル存在を検証
assert_file() {
  local path="$1" msg="$2"
  if [ -f "$path" ]; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (file not found: $path)"
  fi
}

# assert_no_file <path> <message>: ファイル非存在を検証
assert_no_file() {
  local path="$1" msg="$2"
  if [ ! -e "$path" ]; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (unexpected file exists: $path)"
  fi
}

# assert_match <regex> <file> <message>: ファイル内容の正規表現一致を検証
assert_match() {
  local regex="$1" file="$2" msg="$3"
  if [ -f "$file" ] && grep -qE "$regex" "$file"; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (no match for /$regex/ in $file)"
  fi
}

# setup / teardown（log_rotate.bats setup() と同一前提）
setup() {
  TMP="$(mktemp -d)"
  export HOME="$TMP"   # log.sh の LOG_DIR 既定を一時領域に向け、実ログを汚さない
  export LOG_DIR="$TMP/logdir"; mkdir -p "$LOG_DIR/.locks"
  # shellcheck source=../lib/lock.sh
  source "$SCRIPT_DIR/../lib/lock.sh"
  # shellcheck source=../lib/log.sh
  source "$SCRIPT_DIR/../lib/log.sh"
  # log.sh の source 中で LOG_DIR が再代入されるため、テスト用に再設定
  LOG_DIR="$TMP/logdir"; export LOG_DIR
}
teardown() { chmod -R 755 "$TMP" 2>/dev/null || true; rm -rf "$TMP"; }

# ===== UC1 サイズ超過ローテート =====

setup
# シナリオ: monitor.log が上限を超えると世代退避され本体が小さくなる（01 UC1-S1）。
# Given: 上限 100B に対し 200B の monitor.log
export MHK_ROTATE_MAX_BYTES=100; export MHK_ROTATE_KEEP_GENERATIONS=3
head -c 200 /dev/zero | tr '\0' 'a' > "$LOG_DIR/monitor.log"
# When: rotate_logs を実行
rotate_logs
# Then: 本体は上限以下になり、.1 が生成される
assert_le "$(file_size_bytes "$LOG_DIR/monitor.log")" 100 "UC1-S1: monitor.log body <= limit after rotate"
assert_file "$LOG_DIR/monitor.log.1" "UC1-S1: monitor.log.1 generation created"
teardown

setup
# シナリオ: 上限未満なら何もしない（01 UC1-S2）。
# Given: 上限 1000B に対し 50B の monitor.log
export MHK_ROTATE_MAX_BYTES=1000
head -c 50 /dev/zero | tr '\0' 'a' > "$LOG_DIR/monitor.log"
before=$(file_size_bytes "$LOG_DIR/monitor.log")
# When: rotate_logs を実行
rotate_logs
# Then: サイズ不変・退避なし
assert_eq "$before" "$(file_size_bytes "$LOG_DIR/monitor.log")" "UC1-S2: under-limit monitor.log size unchanged"
assert_no_file "$LOG_DIR/monitor.log.1" "UC1-S2: no generation file created"
teardown

# ===== UC2 out/err の対象化 =====

setup
# シナリオ: 上限超過の .err が切り詰め/退避され、対象外拡張子は不変（01 UC2-S1）。
# Given: 上限 100B に対し 300B の launchd.monitor.err と対象外の note.txt
export MHK_ROTATE_MAX_BYTES=100; export MHK_ROTATE_EXTS="log out err"
head -c 300 /dev/zero | tr '\0' 'a' > "$LOG_DIR/launchd.monitor.err"
head -c 300 /dev/zero | tr '\0' 'a' > "$LOG_DIR/note.txt"
# When: rotate_logs を実行
rotate_logs
# Then: .err は上限以下、対象外の .txt は不変
assert_le "$(file_size_bytes "$LOG_DIR/launchd.monitor.err")" 100 "UC2-S1: .err body <= limit after rotate"
assert_eq 300 "$(file_size_bytes "$LOG_DIR/note.txt")" "UC2-S1: non-target .txt unchanged"
teardown

# ===== UC3 排他制御 =====

setup
# シナリオ: 2 サブシェルが同時に cooldown を with_lock 下で更新しても記録が壊れない（01 UC3-S1）。
# Given: 一時 LOG_DIR/.locks と COOLDOWN_FILE、with_lock 下のインクリメント関数
export COOLDOWN_FILE="$TMP/cd"; : > "$COOLDOWN_FILE"
append_line() { with_lock notify-cooldown bash -c 'grep -v "^k:" "$COOLDOWN_FILE" > "$COOLDOWN_FILE.tmp" 2>/dev/null || true; echo "k:$(date +%s)" >> "$COOLDOWN_FILE.tmp"; mv "$COOLDOWN_FILE.tmp" "$COOLDOWN_FILE"'; }
export -f append_line with_lock acquire_lock release_lock _lock_base_dir record_rotation_error
# When: 2 サブシェルを並行起動し両方の完了を待つ
( append_line ) & p1=$!
( append_line ) & p2=$!
wait "$p1"; wait "$p2"
# Then: COOLDOWN_FILE は key:epoch 形式の行のみ・tmp 残骸なし（破損なし）
assert_match "^k:[0-9]+$" "$COOLDOWN_FILE" "UC3-S1: COOLDOWN_FILE keeps key:epoch form (no corruption)"
assert_no_file "$COOLDOWN_FILE.tmp" "UC3-S1: no leftover .tmp after concurrent updates"
teardown

# ===== UC4 失敗の可視化 =====

setup
# シナリオ: 書き込み失敗時にエラーを記録し沈黙せず処理を継続する（01 UC4-S1）。
# Given: 上限超の monitor.log を持つ LOG_DIR を読み取り専用にし、記録先は別の書込可ディレクトリ
if [ "$(id -u)" -eq 0 ]; then
  echo "  skip - UC4-S1: root では chmod 555 が効かないためスキップ"
else
  export MHK_ROTATE_MAX_BYTES=100
  head -c 300 /dev/zero | tr '\0' 'a' > "$LOG_DIR/monitor.log"
  ERR_DIR="$TMP/errout"; mkdir -p "$ERR_DIR"; export ROTATE_ERR_FILE="$ERR_DIR/rotate.err"
  chmod 555 "$LOG_DIR"
  # When: rotate_logs を実行（失敗しても継続）
  rotate_logs 2>/dev/null; status=$?
  chmod 755 "$LOG_DIR"
  # Then: 非 0 で落ちず、rotate.err にエラーが記録される
  assert_status 0 "$status" "UC4-S1: rotate_logs does not abort on mv failure"
  assert_match "\[ERROR\] \[rotate\]" "$ROTATE_ERR_FILE" "UC4-S1: rotation error recorded to rotate.err"
fi
teardown

# ===== 共通終了処理（冪等） =====

setup
# シナリオ: finalize_job を 2 回呼んでも安全（冪等）（03 §2.4.4）。
# Given: 上限超の monitor.log
export MHK_ROTATE_MAX_BYTES=100
head -c 300 /dev/zero | tr '\0' 'a' > "$LOG_DIR/monitor.log"
# When: finalize_job を 2 回呼ぶ
finalize_job monitor
# And (When): 2 回目の finalize_job
finalize_job monitor; status=$?
# Then: 正常終了し本体は上限以下
assert_status 0 "$status" "finalize_job: idempotent second call returns 0"
assert_le "$(file_size_bytes "$LOG_DIR/monitor.log")" 100 "finalize_job: body <= limit after repeated calls"
teardown

# ===== A 回帰: should_notify にロック付与後も挙動不変 =====

setup
# シナリオ: ロックを足しても cooldown 経過時に通知し記録を更新する（A UC3-S2 回帰・03 §2.7.4）。
# Given: .locks ありの LOG_DIR と十分過去の swap:last
export COOLDOWN_FILE="$TMP/cd"; export NOTIFICATION_COOLDOWN_MIN=60
echo "swap:$(($(date +%s) - 99999))" > "$COOLDOWN_FILE"
# shellcheck source=../bin/notification_cooldown.sh
source "$SCRIPT_DIR/../bin/notification_cooldown.sh"
# When: should_notify swap を呼ぶ
should_notify "swap"; status=$?
# Then: 戻り値 0 かつ key:epoch 形式で更新（A UC3-S2 と同一期待・回帰）
assert_status 0 "$status" "A regression: should_notify returns 0 when elapsed (with lock)"
assert_match "^swap:[0-9]+$" "$COOLDOWN_FILE" "A regression: COOLDOWN_FILE updated in key:epoch form (with lock)"
teardown

setup
# シナリオ: ロックを足しても cooldown 未経過なら通知しない（A UC3-S1 回帰）。
# Given: .locks ありの LOG_DIR と直近の swap:last
export COOLDOWN_FILE="$TMP/cd"; export NOTIFICATION_COOLDOWN_MIN=60
echo "swap:$(($(date +%s) - 10))" > "$COOLDOWN_FILE"
# shellcheck source=../bin/notification_cooldown.sh
source "$SCRIPT_DIR/../bin/notification_cooldown.sh"
# When: should_notify swap を呼ぶ
should_notify "swap"; status=$?
# Then: 戻り値 1（非通知・回帰）
assert_status 1 "$status" "A regression: should_notify returns 1 when cooldown not elapsed (with lock)"
teardown

# --- 集計 ---
echo ""
echo "log_rotate tests: $PASS passed, $FAIL failed"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
exit 0
