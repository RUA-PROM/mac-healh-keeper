#!/bin/bash
# Mac Health Keeper - メトリクス取得（純粋パース + 実コマンドラッパ・source 用）
#
# メトリクス取得という単一責務に閉じる。閾値判定（notification_cooldown.sh）・
# 通知（notify.sh）・ログ（log.sh）・閾値設定（thresholds.sh）は持ち込まず、
# これらを source もしない（一方向依存）。mac-health status と monitor.sh から
# source して使い、テスト（metrics.bats / metrics_test.sh）からも同じ純粋パース関数を
# source して固定入力で検証する。
#
# 構成（notification_cooldown.sh と同方式の Functional Core / Imperative Shell）:
#   - 純粋パース関数（metrics_parse_* / metrics_uptime_days / metrics_uptime_hours）:
#       コマンド出力テキスト・ページ数・epoch を引数で受け、外部コマンドに依存しない。
#       丸め・単位・フォールバックは 02 §3.1.3 の表に従う。
#   - 取得ラッパ関数（metrics_*_* / metrics_docker_status）:
#       実コマンド（sysctl/vm_stat/uptime/memory_pressure/pgrep/docker）を実行し、
#       出力を純粋パース関数に委譲して標準出力に値を 1 つ返す。
#
# 単位記号・"?"/"—"/"%" の付与やラベル整形は呼び出し元（mac-health/monitor.sh/Swift）が
# 現状どおり行う。本ファイルは裸の値（例 swap=512、compressed=0.0、free=78）を返す。

# ===== 純粋パース関数（外部コマンド非依存・テスト対象） =====

# metrics_parse_swap_mb <swapusage テキスト>
#   monitor.sh L27 と同一: "used = ([0-9.]+)M" を抽出し %d で整数化（切り捨て）。
#   パターン不一致・空入力は 0（monitor 互換）。
metrics_parse_swap_mb() {
  local text="${1:-}"
  local v
  v=$(printf '%s' "$text" | sed -E 's/.*used = ([0-9.]+)M.*/\1/' | awk '{printf "%d", $1}')
  printf '%s' "${v:-0}"
}

# metrics_parse_swap_raw <swapusage テキスト>
#   mac-health status L50 と同一: "used = ([0-9.]+M)" を抽出（"512.00M" 形式の文字列）。
#   抽出不可・空入力は空文字（呼び出し元が "?"/"—" を付与）。
metrics_parse_swap_raw() {
  local text="${1:-}"
  printf '%s' "$text" | sed -E 's/.*used = ([0-9.]+M).*/\1/'
}

# metrics_parse_compressed_gb <compressor ページ数>
#   monitor.sh L33 / mac-health L63 と同一: p*4096/1024/1024/1024 を %.1f。
#   空/非数値は 0 扱い → 0.0。
metrics_parse_compressed_gb() {
  local pages="${1:-0}"
  awk -v p="$pages" 'BEGIN { if (p == "" || p+0 != p) p = 0; printf "%.1f", p * 4096 / 1024 / 1024 / 1024 }'
}

# metrics_parse_load_1m <uptime テキスト>
#   monitor.sh L36 と同一: "load averages: X ..." の X を抽出し %.1f（小数1桁）。
#   抽出不可・空入力は 0（monitor 互換）。
metrics_parse_load_1m() {
  local text="${1:-}"
  local v
  v=$(printf '%s' "$text" | sed -E 's/.*load averages?:?[[:space:]]+([0-9.]+).*/\1/' | awk '{printf "%.1f", $1}')
  printf '%s' "${v:-0}"
}

# metrics_parse_load_1m_raw <uptime テキスト>
#   mac-health status L51 と同一: "load averages: X ..." の X を %.1f 整形せず素のまま抽出。
#   mac-health は元々 sed 抽出のみ（小数桁を丸めない）のため、書式完全不変のため raw を提供する。
#   抽出不可・空入力は空文字（呼び出し元が "—" を付与）。
metrics_parse_load_1m_raw() {
  local text="${1:-}"
  printf '%s' "$text" | sed -E 's/.*load averages?:?[[:space:]]+([0-9.]+).*/\1/'
}

# metrics_parse_free_pct <memory_pressure テキスト>
#   monitor.sh L45 / mac-health L66 と同一: "memory free percentage: X%" の X を抽出（換算なし整数）。
#   抽出不可・空入力は空文字（呼び出し元が 100 / "?" を付与）。
metrics_parse_free_pct() {
  local text="${1:-}"
  printf '%s' "$text" | awk -F': ' '/memory free percentage/ {gsub("%","",$2); print $2}'
}

# metrics_uptime_days <now epoch> <boot epoch>
#   mac-health L56 と同一: (now-boot)/86400（整数除算）。boot 空時は now を代入（差 0）。
metrics_uptime_days() {
  local now="${1:-0}" boot="${2:-}"
  [ -z "$boot" ] && boot="$now"
  printf '%s' "$(( (now - boot) / 86400 ))"
}

# metrics_uptime_hours <now epoch> <boot epoch>
#   mac-health L57 と同一: (now-boot)%86400/3600（整数除算）。boot 空時は now を代入（差 0）。
metrics_uptime_hours() {
  local now="${1:-0}" boot="${2:-}"
  [ -z "$boot" ] && boot="$now"
  printf '%s' "$(( (now - boot) % 86400 / 3600 ))"
}

# ===== 取得ラッパ関数（実コマンド実行） =====

# metrics_swap_used_mb: swap 使用量(MB 整数)。monitor.sh 用。
metrics_swap_used_mb() {
  local text
  text=$(sysctl -n vm.swapusage 2>/dev/null)
  metrics_parse_swap_mb "$text"
}

# metrics_swap_used_raw: swap 使用量("512.00M" 文字列)。mac-health status 表示用。
metrics_swap_used_raw() {
  local text
  text=$(sysctl -n vm.swapusage 2>/dev/null)
  metrics_parse_swap_raw "$text"
}

# metrics_compressed_gb: 圧縮メモリ(GB・小数1桁)。
metrics_compressed_gb() {
  local pages
  pages=$(vm_stat 2>/dev/null | awk '/Pages occupied by compressor/ {gsub("\\.",""); print $5}')
  metrics_parse_compressed_gb "${pages:-0}"
}

# metrics_load_1m: Load Avg(1分・小数1桁)。monitor.sh 判定用。
metrics_load_1m() {
  local text
  text=$(uptime 2>/dev/null)
  metrics_parse_load_1m "$text"
}

# metrics_load_1m_raw: Load Avg(1分・素の抽出値)。mac-health status 表示用（書式不変）。
metrics_load_1m_raw() {
  local text
  text=$(uptime 2>/dev/null)
  metrics_parse_load_1m_raw "$text"
}

# metrics_memory_free_pct: メモリ空き率(%整数)。抽出不可は空文字（呼び出し元が既定値付与）。
metrics_memory_free_pct() {
  local text
  text=$(memory_pressure 2>/dev/null)
  metrics_parse_free_pct "$text"
}

# metrics_uptime_days_now: 稼働日数(実 boot 取得)。
metrics_uptime_days_now() {
  local boot now
  boot=$(sysctl -n kern.boottime 2>/dev/null | awk '{print $4}' | tr -d ',')
  now=$(date +%s)
  metrics_uptime_days "$now" "$boot"
}

# metrics_uptime_hours_now: 稼働時間端数(実 boot 取得)。
metrics_uptime_hours_now() {
  local boot now
  boot=$(sysctl -n kern.boottime 2>/dev/null | awk '{print $4}' | tr -d ',')
  now=$(date +%s)
  metrics_uptime_hours "$now" "$boot"
}

# metrics_docker_status: 稼働中 "running\t<n>"（数取得不可は "running\t?"）、非稼働 "stopped"。
#   呼び出し元（mac-health は "running (containers=%s)" / "not running"）が現状書式に整形する。
metrics_docker_status() {
  if pgrep -f "com\.apple\.Virtualization\.VirtualMachine" >/dev/null 2>&1 \
     || pgrep -xf "/Applications/Docker.app/Contents/MacOS/Docker Desktop.app/Contents/MacOS/Docker Desktop" >/dev/null 2>&1; then
    local ccount
    ccount=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')
    printf 'running\t%s' "${ccount:-?}"
  else
    printf 'stopped'
  fi
}

# ===== CLI ディスパッチ（直接実行時のみ・サブ F 02 §3.4） =====
#
# Swift（MetricsCollector）から `metrics.sh <metric>` の引数呼び出しで取得関数を 1 回起動するための
# 薄いエントリ。BASH_SOURCE 判定により **直接実行時のみ** dispatch し、source 利用
# （mac-health / monitor.sh / metrics.bats / metrics_test.sh）は従来どおり関数定義のみで不変。
# メトリクス名は Swift 側の固定列挙であり補間値（ユーザー入力）は流入しない（注入面なし）。
# 未知の metric は非 0 終了（出力なし）で安全に扱う。
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  case "${1:-}" in
    load)         metrics_load_1m_raw ;;
    swap)         metrics_swap_used_raw ;;
    free)         metrics_memory_free_pct ;;
    compressed)   metrics_compressed_gb ;;
    uptime_days)  metrics_uptime_days_now ;;
    uptime_hours) metrics_uptime_hours_now ;;
    docker)       metrics_docker_status ;;
    *)            exit 2 ;;
  esac
fi
