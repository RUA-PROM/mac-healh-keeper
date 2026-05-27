#!/bin/bash
# Mac Health Keeper - notification_cooldown.sh の単体テスト（bats 不在時の自前 assert ランナー）
#
# monitor.bats と同一 source・同一前提で UC3-S1/S2・UC4-S1〜S6（計 8 ケース）を再現する。
# bats が無い環境（01 §3.4 / 02 §3.3 のフォールバック）で `make test` から呼ばれる。
# 失敗が 1 件でもあれば非 0 終了する。破壊的副作用なし（一時 COOLDOWN_FILE / notify 不使用）。
#
# BDD 形式（ユースケース → シナリオ → Given/When/Then）は .agents/TEST_BDD_FORMAT.md に従う。
# ユースケース: 通知のクールダウンを COOLDOWN_FILE 基準で制御し、各メトリクスの閾値超過を判定する。

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0

# --- 自前 assert ヘルパ ---

# assert_status <expected> <actual> <message>: 終了コード一致を検証
assert_status() {
  local expected="$1" actual="$2" msg="$3"
  if [ "$actual" -eq "$expected" ]; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (expected status $expected, got $actual)"
  fi
}

# assert_eq <expected> <actual> <message>: 文字列一致を検証
assert_eq() {
  local expected="$1" actual="$2" msg="$3"
  if [ "$actual" = "$expected" ]; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (expected '$expected', got '$actual')"
  fi
}

# assert_match <regex> <file> <message>: ファイル内容の正規表現一致を検証
assert_match() {
  local regex="$1" file="$2" msg="$3"
  if grep -qE "$regex" "$file"; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (no match for /$regex/ in $file)"
  fi
}

# setup / teardown（bats setup() と同一前提）
setup() {
  TMP="$(mktemp -d)"
  export COOLDOWN_FILE="$TMP/cd"
  export NOTIFICATION_COOLDOWN_MIN=60
  # shellcheck source=../bin/notification_cooldown.sh
  source "$SCRIPT_DIR/../bin/notification_cooldown.sh"
}
teardown() { rm -rf "$TMP"; }

# --- UC3 通知クールダウン判定 ---

setup
# シナリオ: cooldown 未経過なら通知しない（01 UC3-S1）。
# Given: swap の last=現在直近（now-10秒）を記録
echo "swap:$(($(date +%s) - 10))" > "$COOLDOWN_FILE"
# When: should_notify swap を呼ぶ
should_notify "swap"; status=$?
# Then: 戻り値 1（非通知）
assert_status 1 "$status" "UC3-S1: should_notify returns 1 when cooldown not elapsed"
teardown

setup
# シナリオ: cooldown 経過なら通知し記録を更新する（01 UC3-S2）。
# Given: swap の last=十分過去（now-99999秒）を記録
echo "swap:$(($(date +%s) - 99999))" > "$COOLDOWN_FILE"
# When: should_notify swap を呼ぶ
should_notify "swap"; status=$?
# Then: 戻り値 0（通知）かつ COOLDOWN_FILE が key:epoch 形式で更新
assert_status 0 "$status" "UC3-S2: should_notify returns 0 when elapsed"
assert_match "^swap:[0-9]+$" "$COOLDOWN_FILE" "UC3-S2: COOLDOWN_FILE updated in key:epoch form"
teardown

# --- UC4 メトリクス閾値判定 ---

setup
# シナリオ: swap 閾値以上は真（01 UC4-S1）。
# Given: swap_used_mb=6000, 閾値5000
# When: exceeds_threshold 6000 5000
exceeds_threshold 6000 5000; status=$?
# Then: 終了コード0（真）
assert_status 0 "$status" "UC4-S1: exceeds_threshold true when swap >= threshold"
teardown

setup
# シナリオ: swap 閾値未満は偽（01 UC4-S2）。
# Given: swap_used_mb=4000, 閾値5000
# When: exceeds_threshold 4000 5000
exceeds_threshold 4000 5000; status=$?
# Then: 終了コード1（偽）
assert_status 1 "$status" "UC4-S2: exceeds_threshold false when swap < threshold"
teardown

setup
# シナリオ: compressed 閾値以上は真（01 UC4-S3）。
# Given: compressed_int=10, 閾値10
# When: exceeds_threshold 10 10
exceeds_threshold 10 10; status=$?
# Then: 終了コード0（真, 境界 >=）
assert_status 0 "$status" "UC4-S3: exceeds_threshold true when compressed >= threshold"
teardown

setup
# シナリオ: load が ncpu×倍率以上は真（01 UC4-S4）。
# Given: ncpu=8, multiplier=10 → 閾値80, load_int=80
# When: exceeds_threshold 80 $((8*10))
exceeds_threshold 80 $((8 * 10)); status=$?
# Then: 終了コード0（真）
assert_status 0 "$status" "UC4-S4: exceeds_threshold true when load >= ncpu*multiplier"
teardown

setup
# シナリオ: free_pct<10 は critical（01 UC4-S5）。
# Given: free_pct=5
# When: classify_pressure 5
output=$(classify_pressure 5)
# Then: critical
assert_eq "critical" "$output" "UC4-S5: classify_pressure critical when free_pct < 10"
teardown

setup
# シナリオ: free_pct>=25 は normal（01 UC4-S6）。
# Given: free_pct=50
# When: classify_pressure 50
output=$(classify_pressure 50)
# Then: normal（critical ではない）
assert_eq "normal" "$output" "UC4-S6: classify_pressure normal when free_pct >= 25"
teardown

# --- 集計 ---
echo ""
echo "shell tests: $PASS passed, $FAIL failed"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
exit 0
