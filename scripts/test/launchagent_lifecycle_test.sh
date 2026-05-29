#!/bin/bash
# Mac Health Keeper - launchagent_lifecycle.sh の単体テスト
#
# issue: 20260529_122242_LaunchAgentロード失敗調査と修正
#
# `scripts/lib/launchagent_lifecycle.sh` の load_launchagent / verify_launchagent_loaded を
# 「launchctl を mock」する形で BDD テストする。実 launchctl を呼ばないため CI でも安全に
# 実行できる。
#
# BDD 形式（ユースケース → シナリオ → Given/When/Then）は .agents/TEST_BDD_FORMAT.md に従う。
# 01_要件定義.md UC4-S1〜S3 + 境界をカバー。
# `make test-shell` から呼ばれ、失敗が 1 件でもあれば非 0 終了する。
# 破壊的副作用なし（一時 TRACE / 一時 mock launchctl で完結）。
#
# ユースケース:
# load_launchagent が bootout → bootstrap → verify（launchctl print 経由）の冪等シーケンスを
# 実行し、stderr を構造化ログとして残す。verify には launchctl list ではなく launchctl print を
# 用い、RunAtLoad=false な plist でも偽陽性を出さない。

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO_DIR/scripts/lib/launchagent_lifecycle.sh"

PASS=0
FAIL=0

# --- 自前 assert ヘルパ（monitor_test.sh と同流儀） ---

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
  local pattern="$1" file="$2" msg="$3"
  if grep -qE "$pattern" "$file"; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (no match for /$pattern/)"
  fi
}

assert_no_match() {
  local pattern="$1" file="$2" msg="$3"
  if ! grep -qE "$pattern" "$file"; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (unexpected match for /$pattern/)"
  fi
}

# テスト前提
if [ ! -f "$LIB" ]; then
  echo "FAIL: launchagent_lifecycle.sh not found: $LIB" >&2
  exit 1
fi

# --- setup / teardown: 各シナリオで TMP を作り直す（独立性確保） ---

setup() {
  TMP="$(mktemp -d -t mac-health-lifecycle.XXXXXX)"
  TRACE="$TMP/trace.log"
  STDOUT="$TMP/stdout.log"
  : >"$TRACE"
  : >"$STDOUT"
  # mock launchctl を PATH 先頭に挿入する代わりに LAUNCHCTL_BIN で差し替える
  export LIFECYCLE_UID=99999
}

teardown() {
  rm -rf "$TMP"
  unset LIFECYCLE_UID LAUNCHCTL_BIN
}

# mock launchctl 用ヘルパ: scenario ごとに stub スクリプトを生成
make_mock_launchctl() {
  # $1: bootout exit, $2: bootout stderr, $3: bootstrap exit, $4: bootstrap stderr,
  # $5: print stdout, $6: print exit, $7: print stderr
  local bootout_exit="$1" bootout_err="$2"
  local bootstrap_exit="$3" bootstrap_err="$4"
  local print_out="$5" print_exit="$6" print_err="$7"
  cat >"$TMP/mock_launchctl" <<EOF
#!/bin/bash
echo "\$@" >>"$TRACE"
case "\$1" in
  bootout)
    printf '%s' "$bootout_err" >&2
    exit $bootout_exit
    ;;
  bootstrap)
    printf '%s' "$bootstrap_err" >&2
    exit $bootstrap_exit
    ;;
  print)
    printf '%s' "$print_out"
    printf '%s' "$print_err" >&2
    exit $print_exit
    ;;
esac
exit 99
EOF
  chmod +x "$TMP/mock_launchctl"
  export LAUNCHCTL_BIN="$TMP/mock_launchctl"
}

# ===== UC4-S1: 正常系・冪等な bootout → bootstrap → verify =====

setup
# シナリオ: 既ロード状態に対して load_launchagent を呼ぶと bootout → bootstrap → verify（print）の順で
#           launchctl が呼ばれ、戻り値 0 を返す（01 UC4-S1）。
# Given: 既ロード状態を模した mock（bootout 0、bootstrap 0、print は state=not running を返す）
make_mock_launchctl 0 "" 0 "" "gui/99999/X = { state = not running }" 0 ""
# shellcheck source=../lib/launchagent_lifecycle.sh
source "$LIB"
# When: load_launchagent を呼ぶ
load_launchagent "com.example.test.A" "/tmp/A.plist" >"$STDOUT"
status=$?
# Then: 戻り値 0（verify 成功）
assert_status 0 "$status" "UC4-S1: load_launchagent が verify 成功で 0 を返す"
# And (Then): launchctl の呼び出し順序が bootout → bootstrap → print
expected_trace=$'bootout gui/99999/com.example.test.A\nbootstrap gui/99999 /tmp/A.plist\nprint gui/99999/com.example.test.A'
actual_trace=$(cat "$TRACE")
assert_eq "$expected_trace" "$actual_trace" "UC4-S1: 呼び出し順序が bootout → bootstrap → print"
# And (Then): stdout に 3 phase の構造化ログが出る
assert_grep "label=com\.example\.test\.A phase=bootout exit=0" "$STDOUT" "UC4-S1: phase=bootout ログ"
assert_grep "label=com\.example\.test\.A phase=bootstrap exit=0" "$STDOUT" "UC4-S1: phase=bootstrap ログ"
assert_grep "label=com\.example\.test\.A phase=verify exit=0" "$STDOUT" "UC4-S1: phase=verify ログ"
teardown

# ===== UC4-S2: bootstrap 失敗時、stderr が構造化ログに残る =====

setup
# シナリオ: bootstrap が exit 5（Input/output error）を返したとき、stderr 抜粋が構造化ログに残る（01 UC4-S2）。
# Given: bootstrap が exit 5 + 既知の launchctl エラー文言を吐く mock
make_mock_launchctl 0 "" 5 "Bootstrap failed: 5: Input/output error" "" 78 'Could not find service "X" in domain for user gui: 99999'
# shellcheck source=../lib/launchagent_lifecycle.sh
source "$LIB"
# When: load_launchagent を呼ぶ
load_launchagent "com.example.test.B" "/tmp/B.plist" >"$STDOUT"
status=$?
# Then: 戻り値 1（bootstrap も verify も失敗）
assert_status 1 "$status" "UC4-S2: bootstrap 失敗 + verify NG で 1 を返す"
# And (Then): phase=bootstrap exit=5 と stderr 抜粋が出る
assert_grep "phase=bootstrap exit=5" "$STDOUT" "UC4-S2: phase=bootstrap exit=5 ログ"
assert_grep "Bootstrap failed: 5: Input/output error" "$STDOUT" "UC4-S2: stderr 抜粋が残る"
teardown

# ===== UC4-S3: verify は launchctl print のみで判定する（list 偽陽性回避） =====

setup
# シナリオ: 検証 API は launchctl list ではなく launchctl print を呼ぶ（01 UC4-S3 / 偽陽性回避）。
# Given: bootstrap 成功・print が state を返す mock
make_mock_launchctl 0 "" 0 "" "gui/99999/X = { state = not running }" 0 ""
# shellcheck source=../lib/launchagent_lifecycle.sh
source "$LIB"
# When: load_launchagent を呼ぶ
load_launchagent "com.example.test.C" "/tmp/C.plist" >"$STDOUT"
# Then: trace に "list" 呼び出しが含まれない（list を使っていない）
assert_no_match "^list" "$TRACE" "UC4-S3: launchctl list は呼ばれない"
# And (Then): trace に print が含まれる（verify は print 経由）
assert_grep "^print gui/99999/com\.example\.test\.C" "$TRACE" "UC4-S3: launchctl print で verify する"
teardown

# ===== UC4-S4: bootstrap 失敗しても既ロード状態なら verify は成功と扱う（救済パス） =====

setup
# シナリオ: bootstrap が exit 5 でも launchctl print が state を返す場合は loaded と判定し戻り値 0。
# Given: bootstrap exit 5 だが print は state を返す（既ロード状態への再 bootstrap 競合）
make_mock_launchctl 0 "" 5 "Bootstrap failed: 5: Input/output error" "gui/99999/X = { state = not running }" 0 ""
# shellcheck source=../lib/launchagent_lifecycle.sh
source "$LIB"
# When: load_launchagent を呼ぶ
load_launchagent "com.example.test.D" "/tmp/D.plist" >"$STDOUT"
status=$?
# Then: 戻り値 0（救済パスで verify 成功）
assert_status 0 "$status" "UC4-S4: bootstrap 失敗でも verify が loaded なら 0 を返す"
# And (Then): verify ログに救済 stderr が記録される
assert_grep "phase=verify exit=0 stderr=bootstrap-failed-but-verified-loaded" "$STDOUT" "UC4-S4: 救済 verify ログ"
teardown

# ===== UC4-S5: verify_launchagent_loaded 単体 - print が Could not find を返したら NG =====

setup
# シナリオ: print が "Could not find service" を含むとき verify_launchagent_loaded は 1 を返す。
# Given: print が could-not-find を返す mock
make_mock_launchctl 0 "" 0 "" 'Bad request. Could not find service "X" in domain for user gui: 99999' 113 ""
# shellcheck source=../lib/launchagent_lifecycle.sh
source "$LIB"
# When: verify_launchagent_loaded を呼ぶ
verify_launchagent_loaded "com.example.test.E"
status=$?
# Then: 戻り値 1（not loaded）
assert_status 1 "$status" "UC4-S5: print が Could not find なら verify=1"
teardown

# ===== UC4-S6: verify_launchagent_loaded 単体 - print が state を返したら OK =====

setup
# シナリオ: print が state = running を含むとき verify_launchagent_loaded は 0 を返す（loaded）。
# Given: print が state = running を返す mock
make_mock_launchctl 0 "" 0 "" "gui/99999/X = { state = running active count = 1 }" 0 ""
# shellcheck source=../lib/launchagent_lifecycle.sh
source "$LIB"
# When: verify_launchagent_loaded を呼ぶ
verify_launchagent_loaded "com.example.test.F"
status=$?
# Then: 戻り値 0（loaded）
assert_status 0 "$status" "UC4-S6: print が state なら verify=0"
teardown

# ===== UC4-S7: bootout が失敗しても致命と扱わない（idempotent） =====

setup
# シナリオ: bootout が exit 113（未ロード時の典型エラー）でも、bootstrap が成功すれば verify=0 を返す。
# Given: bootout exit 113、bootstrap exit 0、print state あり
make_mock_launchctl 113 "Could not find specified service" 0 "" "gui/99999/X = { state = not running }" 0 ""
# shellcheck source=../lib/launchagent_lifecycle.sh
source "$LIB"
# When: load_launchagent を呼ぶ
load_launchagent "com.example.test.G" "/tmp/G.plist" >"$STDOUT"
status=$?
# Then: 戻り値 0（bootout 失敗を吸収して bootstrap 成功）
assert_status 0 "$status" "UC4-S7: bootout 失敗を idempotent に吸収して verify 成功"
# And (Then): phase=bootout exit=113 のログが残る（失敗事実は隠さず記録）
assert_grep "phase=bootout exit=113" "$STDOUT" "UC4-S7: bootout 失敗ログを残す"
teardown

# ===== UC4-S8: 構造化ログのフォーマット契約（label= phase= exit= stderr=） =====

setup
# シナリオ: 構造化ログは 1 行に label= / phase= / exit= / stderr= の 4 フィールドを必ず含む。
# Given: 全 phase 正常
make_mock_launchctl 0 "" 0 "" "gui/99999/X = { state = not running }" 0 ""
# shellcheck source=../lib/launchagent_lifecycle.sh
source "$LIB"
# When: load_launchagent を呼ぶ
load_launchagent "com.example.test.H" "/tmp/H.plist" >"$STDOUT"
# Then: 全 3 行が "label=… phase=… exit=… stderr=…" の順序契約を満たす
line_count=$(grep -cE "^label=com\.example\.test\.H phase=(bootout|bootstrap|verify) exit=[0-9]+ stderr=" "$STDOUT")
assert_eq "3" "$line_count" "UC4-S8: 3 phase × 4 フィールド契約を満たす"
teardown

# --- 集計 ---
echo ""
echo "launchagent_lifecycle_test: $PASS passed, $FAIL failed"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
exit 0
