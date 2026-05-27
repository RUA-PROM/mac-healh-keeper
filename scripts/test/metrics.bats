#!/usr/bin/env bats
# Mac Health Keeper - metrics.sh の単体テスト（UC1・UC2）
# BDD 形式（ユースケース → シナリオ → Given/When/Then）は .agents/TEST_BDD_FORMAT.md に従う。
# 01 BDD UC1/UC2 と 03 §2.1.4 / §2.5.4 のテスト仕様に対応する。
#
# ユースケース: metrics.sh の純粋パース関数が固定入力に対し既定の単位・丸めで値を返し、
#               2 参照元（mac-health 表示用 raw / monitor 判定用）で整合する。

setup() {
  source "${BATS_TEST_DIRNAME}/../lib/metrics.sh"
}

# --- UC1 メトリクス取得の集約（純粋パース） ---

# シナリオ: vm.swapusage の used を MB 整数で返す（01 UC1-S1）。
@test "metrics_parse_swap_mb returns integer MB" {
  # Given: used = 512.00M を含む swapusage テキスト
  text="total = 2048.00M  used = 512.00M  free = 1536.00M"
  # When: metrics_parse_swap_mb を呼ぶ
  run metrics_parse_swap_mb "$text"
  # Then: 512 が返る（%d 切り捨て整数）
  [ "$output" = "512" ]
}

# シナリオ: compressor ページ数を GB(小数1桁)へ換算する（01 UC1-S2）。
@test "metrics_parse_compressed_gb returns GB with 1 decimal" {
  # Given: compressor ページ数 2621440（2621440*4096/1024^3 = 10.0）
  pages=2621440
  # When: metrics_parse_compressed_gb を呼ぶ
  run metrics_parse_compressed_gb "$pages"
  # Then: 10.0 が返る
  [ "$output" = "10.0" ]
}

# シナリオ: uptime テキストの load を小数1桁へ丸める（monitor 判定用）。
@test "metrics_parse_load_1m rounds to 1 decimal" {
  # Given: load averages: 3.45 を含む uptime テキスト
  text="12:00  up 2 days,  3:00, 2 users, load averages: 3.45 2.10 1.98"
  # When: metrics_parse_load_1m を呼ぶ
  run metrics_parse_load_1m "$text"
  # Then: 3.5 が返る（%.1f 丸め）
  [ "$output" = "3.5" ]
}

# シナリオ: now-boot を 86400 で整数除算し稼働日数を返す。
@test "metrics_uptime_days returns integer days" {
  # Given: now-boot = 200000 秒
  now=200000; boot=0
  # When: metrics_uptime_days を呼ぶ
  run metrics_uptime_days "$now" "$boot"
  # Then: 2 が返る（200000/86400 = 2）
  [ "$output" = "2" ]
}

# シナリオ: compressor ページ数 0 は 0.0（境界値）。
@test "metrics_parse_compressed_gb zero pages returns 0.0" {
  # Given: ページ数 0
  pages=0
  # When: metrics_parse_compressed_gb を呼ぶ
  run metrics_parse_compressed_gb "$pages"
  # Then: 0.0 が返る
  [ "$output" = "0.0" ]
}

# シナリオ: swapusage 空入力は 0（異常系・monitor 互換）。
@test "metrics_parse_swap_mb empty input returns 0" {
  # Given: 空のテキスト
  text=""
  # When: metrics_parse_swap_mb を呼ぶ
  run metrics_parse_swap_mb "$text"
  # Then: 0 が返る
  [ "$output" = "0" ]
}

# --- UC2 参照側の一致（集約前後の出力一致） ---

# シナリオ: 同一入力で 2 参照元（mac-health raw / monitor MB）が整合する（01 UC2-S1）。
@test "swap raw and MB are consistent for both reference sites" {
  # Given: used = 512.00M を含むテキスト
  text="used = 512.00M"
  # When: 表示用 raw と判定用 MB をそれぞれ取得
  raw=$(metrics_parse_swap_raw "$text")
  mb=$(metrics_parse_swap_mb "$text")
  # Then: raw=512.00M（mac-health 書式）、mb=512（monitor 用）で整合
  [ "$raw" = "512.00M" ]
  # And (Then): MB 整数も同一入力から得られる
  [ "$mb" = "512" ]
}

# シナリオ: 同一 swapusage に対し parse_swap_mb は常に同値（2 参照元の冪等性・01 UC2-S1）。
@test "metrics_parse_swap_mb is idempotent for both reference sites" {
  # Given: 固定の swapusage テキスト
  text="used = 777.00M"
  # When: 同じ純粋関数を 2 度呼ぶ（mac-health/monitor.sh の参照を模す）
  a=$(metrics_parse_swap_mb "$text")
  b=$(metrics_parse_swap_mb "$text")
  # Then: 2 参照元で同値
  [ "$a" = "$b" ]
  # And (Then): 期待値 777
  [ "$a" = "777" ]
}

# シナリオ: load は mac-health(raw) と monitor(%.1f) で書式が分かれ、現状書式を維持する（集約前後一致）。
@test "load raw and rounded keep their respective formats" {
  # Given: load averages: 11.39 を含む uptime テキスト
  text="9:00  up 1 day, load averages: 11.39 8.10 6.98"
  # When: mac-health 表示用 raw と monitor 判定用 %.1f をそれぞれ取得
  raw=$(metrics_parse_load_1m_raw "$text")
  rounded=$(metrics_parse_load_1m "$text")
  # Then: raw は素の 11.39（mac-health の現状書式）
  [ "$raw" = "11.39" ]
  # And (Then): 判定用は %.1f の 11.4（monitor の現状書式）
  [ "$rounded" = "11.4" ]
}
