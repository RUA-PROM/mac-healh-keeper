#!/usr/bin/env bats
# Mac Health Keeper - notification_cooldown.sh の単体テスト（UC3・UC4）
# BDD 形式（ユースケース → シナリオ → Given/When/Then）は .agents/TEST_BDD_FORMAT.md に従う。
# 01 BDD UC3/UC4 と 03 §2.4.4 のテスト仕様に 1 対 1 対応する。
#
# ユースケース: 通知のクールダウンを COOLDOWN_FILE 基準で制御し、各メトリクスの閾値超過を判定する。

setup() {
  TMP="$(mktemp -d)"; export COOLDOWN_FILE="$TMP/cd"
  export NOTIFICATION_COOLDOWN_MIN=60
  source "${BATS_TEST_DIRNAME}/../bin/notification_cooldown.sh"
}
teardown() { rm -rf "$TMP"; }

# --- UC3 通知クールダウン判定 ---

# シナリオ: cooldown 未経過なら通知しない（01 UC3-S1）。
@test "should_notify returns 1 when cooldown not elapsed" {
  # Given: swap の last=現在直近（now-10秒）を記録
  echo "swap:$(($(date +%s) - 10))" > "$COOLDOWN_FILE"
  # When: should_notify swap を呼ぶ
  run should_notify "swap"
  # Then: 戻り値 1（非通知）
  [ "$status" -eq 1 ]
}

# シナリオ: cooldown 経過なら通知し記録を更新する（01 UC3-S2）。
@test "should_notify returns 0 and updates file when elapsed" {
  # Given: swap の last=十分過去（now-99999秒）を記録
  echo "swap:$(($(date +%s) - 99999))" > "$COOLDOWN_FILE"
  # When: should_notify swap を呼ぶ
  run should_notify "swap"
  # Then: 戻り値 0（通知）かつ COOLDOWN_FILE が key:epoch 形式で更新
  [ "$status" -eq 0 ]
  grep -qE "^swap:[0-9]+$" "$COOLDOWN_FILE"
}

# --- UC4 メトリクス閾値判定 ---

# シナリオ: swap 閾値以上は真（01 UC4-S1）。
@test "exceeds_threshold true when swap >= threshold" {
  # Given: swap_used_mb=6000, 閾値5000
  # When: exceeds_threshold 6000 5000
  run exceeds_threshold 6000 5000
  # Then: 終了コード0（真）
  [ "$status" -eq 0 ]
}

# シナリオ: swap 閾値未満は偽（01 UC4-S2）。
@test "exceeds_threshold false when swap < threshold" {
  # Given: swap_used_mb=4000, 閾値5000
  # When: exceeds_threshold 4000 5000
  run exceeds_threshold 4000 5000
  # Then: 終了コード1（偽）
  [ "$status" -eq 1 ]
}

# シナリオ: compressed 閾値以上は真（01 UC4-S3）。
@test "exceeds_threshold true when compressed >= threshold" {
  # Given: compressed_int=10, 閾値10
  # When: exceeds_threshold 10 10
  run exceeds_threshold 10 10
  # Then: 終了コード0（真, 境界 >=）
  [ "$status" -eq 0 ]
}

# シナリオ: load が ncpu×倍率以上は真（01 UC4-S4）。
@test "exceeds_threshold true when load >= ncpu*multiplier" {
  # Given: ncpu=8, multiplier=10 → 閾値80, load_int=80
  # When: exceeds_threshold 80 $((8*10))
  run exceeds_threshold 80 $((8 * 10))
  # Then: 終了コード0（真）
  [ "$status" -eq 0 ]
}

# シナリオ: free_pct<10 は critical（01 UC4-S5）。
@test "classify_pressure critical when free_pct < 10" {
  # Given: free_pct=5
  # When: classify_pressure 5
  run classify_pressure 5
  # Then: critical
  [ "$output" = "critical" ]
}

# シナリオ: free_pct>=25 は normal（01 UC4-S6）。
@test "classify_pressure normal when free_pct >= 25" {
  # Given: free_pct=50
  # When: classify_pressure 50
  run classify_pressure 50
  # Then: normal（critical ではない）
  [ "$output" = "normal" ]
  [ "$output" != "critical" ]
}
