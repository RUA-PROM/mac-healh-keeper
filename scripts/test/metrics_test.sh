#!/bin/bash
# Mac Health Keeper - metrics.sh の単体テスト（bats 不在時の自前 assert ランナー）
#
# metrics.bats と同一 source・同一前提で UC1-S1/S2・UC2-S1 と境界・異常系・load 書式維持を再現する。
# bats が無い環境（01 §3.4 / 02 §3.3 のフォールバック）で `make test-shell` から呼ばれる。
# 失敗が 1 件でもあれば非 0 終了する。破壊的副作用なし（純粋パース関数のみ・実コマンド不使用）。
#
# BDD 形式（ユースケース → シナリオ → Given/When/Then）は .agents/TEST_BDD_FORMAT.md に従う。
# ユースケース: metrics.sh の純粋パース関数が固定入力に対し既定の単位・丸めで値を返し、
#               2 参照元（mac-health 表示用 raw / monitor 判定用）で整合する。

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0

# --- 自前 assert ヘルパ（monitor_test.sh と同形式） ---

# assert_eq <expected> <actual> <message>: 文字列一致を検証
assert_eq() {
  local expected="$1" actual="$2" msg="$3"
  if [ "$actual" = "$expected" ]; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (expected '$expected', got '$actual')"
  fi
}

# setup（bats setup() と同一前提）
# shellcheck source=../lib/metrics.sh
source "$SCRIPT_DIR/../lib/metrics.sh"

# --- UC1 メトリクス取得の集約（純粋パース） ---

# シナリオ: vm.swapusage の used を MB 整数で返す（01 UC1-S1）。
# Given: used = 512.00M を含む swapusage テキスト
text="total = 2048.00M  used = 512.00M  free = 1536.00M"
# When: metrics_parse_swap_mb を呼ぶ
out=$(metrics_parse_swap_mb "$text")
# Then: 512 が返る（%d 切り捨て整数）
assert_eq "512" "$out" "UC1-S1: metrics_parse_swap_mb returns integer MB"

# シナリオ: compressor ページ数を GB(小数1桁)へ換算する（01 UC1-S2）。
# Given: compressor ページ数 2621440（2621440*4096/1024^3 = 10.0）
pages=2621440
# When: metrics_parse_compressed_gb を呼ぶ
out=$(metrics_parse_compressed_gb "$pages")
# Then: 10.0 が返る
assert_eq "10.0" "$out" "UC1-S2: metrics_parse_compressed_gb returns GB(1dp)"

# シナリオ: uptime テキストの load を小数1桁へ丸める（monitor 判定用）。
# Given: load averages: 3.45 を含む uptime テキスト
text="12:00  up 2 days,  3:00, 2 users, load averages: 3.45 2.10 1.98"
# When: metrics_parse_load_1m を呼ぶ
out=$(metrics_parse_load_1m "$text")
# Then: 3.5 が返る（%.1f 丸め）
assert_eq "3.5" "$out" "UC1: metrics_parse_load_1m rounds to 1 decimal"

# シナリオ: now-boot を 86400 で整数除算し稼働日数を返す。
# Given: now-boot = 200000 秒
now=200000; boot=0
# When: metrics_uptime_days を呼ぶ
out=$(metrics_uptime_days "$now" "$boot")
# Then: 2 が返る（200000/86400 = 2）
assert_eq "2" "$out" "UC1: metrics_uptime_days returns integer days"

# シナリオ: compressor ページ数 0 は 0.0（境界値）。
# Given: ページ数 0
pages=0
# When: metrics_parse_compressed_gb を呼ぶ
out=$(metrics_parse_compressed_gb "$pages")
# Then: 0.0 が返る
assert_eq "0.0" "$out" "UC1: metrics_parse_compressed_gb zero pages returns 0.0"

# シナリオ: swapusage 空入力は 0（異常系・monitor 互換）。
# Given: 空のテキスト
text=""
# When: metrics_parse_swap_mb を呼ぶ
out=$(metrics_parse_swap_mb "$text")
# Then: 0 が返る
assert_eq "0" "$out" "UC1: metrics_parse_swap_mb empty input returns 0"

# --- UC2 参照側の一致（集約前後の出力一致） ---

# シナリオ: 同一入力で 2 参照元（mac-health raw / monitor MB）が整合する（01 UC2-S1）。
# Given: used = 512.00M を含むテキスト
text="used = 512.00M"
# When: 表示用 raw と判定用 MB をそれぞれ取得
raw=$(metrics_parse_swap_raw "$text")
mb=$(metrics_parse_swap_mb "$text")
# Then: raw=512.00M（mac-health 書式）、mb=512（monitor 用）で整合
assert_eq "512.00M" "$raw" "UC2-S1: swap raw form for mac-health unchanged"
# And (Then): MB 整数も同一入力から得られる
assert_eq "512" "$mb" "UC2-S1: swap MB integer for monitor matches raw"

# シナリオ: 同一 swapusage に対し parse_swap_mb は常に同値（2 参照元の冪等性・01 UC2-S1）。
# Given: 固定の swapusage テキスト
text="used = 777.00M"
# When: 同じ純粋関数を 2 度呼ぶ（mac-health/monitor.sh の参照を模す）
a=$(metrics_parse_swap_mb "$text")
b=$(metrics_parse_swap_mb "$text")
# Then: 2 参照元で同値
assert_eq "$a" "$b" "UC2-S1: same parse result for both reference sites"
# And (Then): 期待値 777
assert_eq "777" "$a" "UC2-S1: value is the expected MB integer"

# シナリオ: load は mac-health(raw) と monitor(%.1f) で書式が分かれ、現状書式を維持する（集約前後一致）。
# Given: load averages: 11.39 を含む uptime テキスト
text="9:00  up 1 day, load averages: 11.39 8.10 6.98"
# When: mac-health 表示用 raw と monitor 判定用 %.1f をそれぞれ取得
raw=$(metrics_parse_load_1m_raw "$text")
rounded=$(metrics_parse_load_1m "$text")
# Then: raw は素の 11.39（mac-health の現状書式）
assert_eq "11.39" "$raw" "UC2: load raw keeps mac-health current format"
# And (Then): 判定用は %.1f の 11.4（monitor の現状書式）
assert_eq "11.4" "$rounded" "UC2: load rounded keeps monitor current format"

# --- サブ F: CLI ディスパッチ（直接実行）と source 利用不変 ---

METRICS_SH="$SCRIPT_DIR/../lib/metrics.sh"

# シナリオ: metrics.sh の dispatch が対象関数へ委譲し source 利用を壊さない（F・03 §2.4.4）。
# Given: source 後に純粋関数が直接呼べる状態（source 利用が不変であることの確認）
out=$(metrics_parse_swap_raw "used = 512.00M")
# When/Then: source 経由の既存挙動が従来どおり（512.00M）
assert_eq "512.00M" "$out" "F-T4: source 利用の純粋パース関数は不変"

# シナリオ: metrics.sh swap を直接実行すると metrics_swap_used_raw 同値（固定 sysctl を PATH で注入）。
# Given: vm.swapusage を固定出力する stub sysctl を PATH 先頭に置く
STUB_DIR=$(mktemp -d)
cat > "$STUB_DIR/sysctl" <<'STUB'
#!/bin/bash
# vm.swapusage 引数のときだけ固定値を返す（他はパススルー不要・テスト用途）
if [ "$2" = "vm.swapusage" ]; then
  printf 'total = 2048.00M  used = 512.00M  free = 1536.00M\n'
else
  printf '\n'
fi
STUB
chmod +x "$STUB_DIR/sysctl"
# When: metrics.sh swap を直接実行する
out=$(PATH="$STUB_DIR:$PATH" bash "$METRICS_SH" swap)
# Then: metrics_swap_used_raw と同値（"512.00M"）が返る
assert_eq "512.00M" "$out" "F-T4: metrics.sh swap (direct) == metrics_swap_used_raw"

# シナリオ: metrics.sh load を直接実行すると metrics_load_1m_raw 同値（固定 uptime を PATH で注入）。
# Given: uptime を固定出力する stub を PATH 先頭に置く
cat > "$STUB_DIR/uptime" <<'STUB'
#!/bin/bash
printf '9:00  up 1 day, load averages: 11.39 8.10 6.98\n'
STUB
chmod +x "$STUB_DIR/uptime"
# When: metrics.sh load を直接実行する
out=$(PATH="$STUB_DIR:$PATH" bash "$METRICS_SH" load)
# Then: metrics_load_1m_raw と同値（"11.39"）が返る
assert_eq "11.39" "$out" "F-T4: metrics.sh load (direct) == metrics_load_1m_raw"

# シナリオ: 未知の metric は非 0 終了で安全（注入面なし・既定）。
# Given: 未知のメトリクス名
# When: metrics.sh bogus を直接実行する
PATH="$STUB_DIR:$PATH" bash "$METRICS_SH" bogus >/dev/null 2>&1
rc=$?
# Then: 非 0 終了する（未知 metric の安全な扱い）
if [ "$rc" -ne 0 ]; then
  PASS=$((PASS + 1)); echo "  ok   - F-T4: metrics.sh unknown metric exits non-zero"
else
  FAIL=$((FAIL + 1)); echo "  FAIL - F-T4: metrics.sh unknown metric exits non-zero (rc=$rc)"
fi

# シナリオ: dispatch 追加後も source 利用で純粋関数が従来どおり動く（再確認・回帰）。
# Given: dispatch 追加後の metrics.sh を再 source（直接実行でないため dispatch は発火しない）
source "$METRICS_SH"
# When: 純粋関数を呼ぶ
out=$(metrics_parse_load_1m "12:00  up 2 days, load averages: 3.45 2.10 1.98")
# Then: 従来どおり %.1f 丸めの 3.5（source 利用不変）
assert_eq "3.5" "$out" "F-T4: source 利用は dispatch 追加後も不変"

rm -rf "$STUB_DIR"

# --- 集計 ---
echo ""
echo "metrics shell tests: $PASS passed, $FAIL failed"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
exit 0
