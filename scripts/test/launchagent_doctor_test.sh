#!/bin/bash
# Mac Health Keeper - launchagent-doctor.sh の単体テスト
#
# issue: 20260529_122242_LaunchAgentロード失敗調査と修正
#
# `scripts/bin/launchagent-doctor.sh` の出力契約・終了コードを「launchctl を mock」した
# 形で BDD テストする。実 launchctl を呼ばないため CI でも安全に実行できる。
#
# BDD 形式（ユースケース → シナリオ → Given/When/Then）は .agents/TEST_BDD_FORMAT.md に従う。
# 01_要件定義.md UC5-S1 / UC5-S2 + 境界をカバー。
# `make test-shell` から呼ばれ、失敗が 1 件でもあれば非 0 終了する。
# 破壊的副作用なし（一時 dir / mock で完結）。
#
# ユースケース:
# launchagent-doctor は 4 件 LaunchAgent の状態を launchctl print 経由で診断し、
# 構造化ログ + サマリ + 終了コード（全件 loaded=0、1 件でも NG=1）で返す。

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOCTOR="$REPO_DIR/scripts/bin/launchagent-doctor.sh"

PASS=0
FAIL=0

assert_status() {
  local expected="$1" actual="$2" msg="$3"
  if [ "$actual" -eq "$expected" ]; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (expected status $expected, got $actual)"
  fi
}

assert_grep_text() {
  local pattern="$1" text="$2" msg="$3"
  if printf '%s' "$text" | grep -qE "$pattern"; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (no match for /$pattern/)"
  fi
}

assert_no_match_text() {
  local pattern="$1" text="$2" msg="$3"
  if ! printf '%s' "$text" | grep -qE "$pattern"; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (unexpected match for /$pattern/)"
  fi
}

if [ ! -x "$DOCTOR" ]; then
  echo "FAIL: launchagent-doctor.sh not found or not executable: $DOCTOR" >&2
  exit 1
fi

setup() {
  TMP="$(mktemp -d -t mac-health-doctor.XXXXXX)"
}
teardown() {
  rm -rf "$TMP"
  unset DOCTOR_UID DOCTOR_LABELS LAUNCHCTL_BIN
}

# mock launchctl: print の応答を「label → 応答ファイル」マップで指定
# $1: label，$2: 応答ファイル（stdout に出す）
make_mock_with_responses() {
  cat >"$TMP/mock_launchctl" <<'EOF'
#!/bin/bash
# args: print gui/<uid>/<label>
case "$1" in
  print)
    label="${2##*/}"
    f="$MOCK_DIR/${label}.txt"
    rc_f="$MOCK_DIR/${label}.rc"
    if [ -f "$f" ]; then
      cat "$f"
    fi
    if [ -f "$rc_f" ]; then
      exit "$(cat "$rc_f")"
    fi
    exit 0
    ;;
esac
exit 99
EOF
  chmod +x "$TMP/mock_launchctl"
  export LAUNCHCTL_BIN="$TMP/mock_launchctl"
  export MOCK_DIR="$TMP/responses"
  mkdir -p "$MOCK_DIR"
}

# 応答ファイルを書く（ヘルパ）
respond() {
  # $1: label，$2: stdout 内容，$3: exit code
  local label="$1" out="$2" rc="${3:-0}"
  printf '%s' "$out" >"$MOCK_DIR/${label}.txt"
  printf '%s' "$rc" >"$MOCK_DIR/${label}.rc"
}

# ===== UC5-S1: 4 件すべて loaded で exit 0、"4/4 loaded" サマリ =====

setup
# シナリオ: 4 件すべて launchctl print が state を返すと exit 0 + "4/4 loaded"（01 UC5-S1）。
# Given: 4 件すべて state = not running を返す mock
make_mock_with_responses
export DOCTOR_UID=99999
export DOCTOR_LABELS="com.example.a com.example.b com.example.c com.example.d"
for l in com.example.a com.example.b com.example.c com.example.d; do
  respond "$l" "gui/99999/$l = { state = not running }" 0
done
# When: doctor を実行
out=$(bash "$DOCTOR")
rc=$?
# Then: exit 0
assert_status 0 "$rc" "UC5-S1: 4 件 loaded で exit 0"
# And (Then): stdout に "4/4 loaded" サマリが含まれる
assert_grep_text "^4/4 loaded$" "$out" "UC5-S1: 4/4 loaded サマリ"
# And (Then): 各 label の構造化ログが含まれる（status=loaded）
assert_grep_text "label=com\.example\.a status=loaded" "$out" "UC5-S1: label=a status=loaded ログ"
assert_grep_text "label=com\.example\.d status=loaded" "$out" "UC5-S1: label=d status=loaded ログ"
teardown

# ===== UC5-S2: 1 件のみ not-loaded、exit 1 + "3/4 loaded (NG: …)" =====

setup
# シナリオ: 1 件 not-loaded（Could not find）で exit 1 + サマリに NG ラベル（01 UC5-S2）。
# Given: 3 件 loaded、1 件（c）が Could not find を返す mock
make_mock_with_responses
export DOCTOR_UID=99999
export DOCTOR_LABELS="com.example.a com.example.b com.example.c com.example.d"
respond "com.example.a" "gui/99999/com.example.a = { state = not running }" 0
respond "com.example.b" "gui/99999/com.example.b = { state = running }" 0
respond "com.example.c" "Bad request. Could not find service \"com.example.c\" in domain for user gui: 99999" 113
respond "com.example.d" "gui/99999/com.example.d = { state = not running }" 0
# When: doctor を実行
set +e
out=$(bash "$DOCTOR")
rc=$?
set -u
# Then: exit 1（失敗があれば非 0）
assert_status 1 "$rc" "UC5-S2: 1 件 NG で exit 1"
# And (Then): "3/4 loaded (NG: c)" サマリ
assert_grep_text "^3/4 loaded \(NG: c\)$" "$out" "UC5-S2: 3/4 loaded (NG: c) サマリ"
# And (Then): "1/4 NOT loaded" の補助行
assert_grep_text "^1/4 NOT loaded$" "$out" "UC5-S2: 1/4 NOT loaded 補助行"
# And (Then): c の構造化ログが status=not-loaded
assert_grep_text "label=com\.example\.c status=not-loaded" "$out" "UC5-S2: c の status=not-loaded"
teardown

# ===== UC5-S3: 全件 not-loaded（install 直前等の初期状態）で exit 1 + "0/4 loaded" =====

setup
# シナリオ: 4 件すべて未ロードでも doctor は exit 1 を返し 4 件分のサマリを出す（境界）。
# Given: 4 件すべて Could not find を返す mock
make_mock_with_responses
export DOCTOR_UID=99999
export DOCTOR_LABELS="com.example.a com.example.b com.example.c com.example.d"
for l in com.example.a com.example.b com.example.c com.example.d; do
  respond "$l" "Could not find service \"$l\" in domain for user gui: 99999" 113
done
# When: doctor を実行
set +e
out=$(bash "$DOCTOR")
rc=$?
set -u
# Then: exit 1
assert_status 1 "$rc" "UC5-S3: 全件 NG で exit 1"
# And (Then): サマリは "0/4 loaded (NG: a, b, c, d)"
assert_grep_text "^0/4 loaded \(NG: a, b, c, d\)$" "$out" "UC5-S3: 0/4 loaded (NG: a, b, c, d) サマリ"
# And (Then): どの label にも status=loaded は無い
assert_no_match_text "status=loaded" "$out" "UC5-S3: status=loaded が 1 件も無い"
teardown

# ===== UC5-S4: デフォルト 4 label（DOCTOR_LABELS 未指定）でも正しく動く =====

setup
# シナリオ: DOCTOR_LABELS を指定しない場合は BUNDLE_PREFIX.{monitor,docker,uptime,refresh} を検査する。
# Given: 4 件すべて loaded を返す mock。DOCTOR_LABELS は未指定。
make_mock_with_responses
export DOCTOR_UID=99999
# DOCTOR_LABELS は意図的に未設定
for l in com.github.adachi-tatsuru.machealth.monitor com.github.adachi-tatsuru.machealth.docker com.github.adachi-tatsuru.machealth.uptime com.github.adachi-tatsuru.machealth.refresh; do
  respond "$l" "gui/99999/$l = { state = not running }" 0
done
# When: doctor を実行
out=$(bash "$DOCTOR")
rc=$?
# Then: exit 0 + 4/4 loaded
assert_status 0 "$rc" "UC5-S4: デフォルト 4 label で exit 0"
assert_grep_text "^4/4 loaded$" "$out" "UC5-S4: デフォルト 4 label で 4/4 loaded"
# And (Then): デフォルトの 4 label（monitor/docker/uptime/refresh）が全て出力に含まれる
assert_grep_text "label=com\.github\.adachi-tatsuru\.machealth\.monitor" "$out" "UC5-S4: monitor label がログに出る"
assert_grep_text "label=com\.github\.adachi-tatsuru\.machealth\.docker" "$out" "UC5-S4: docker label がログに出る"
teardown

# --- 集計 ---
echo ""
echo "launchagent_doctor_test: $PASS passed, $FAIL failed"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
exit 0
