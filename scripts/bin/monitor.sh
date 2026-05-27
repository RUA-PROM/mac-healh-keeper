#!/bin/bash
# Mac Health Keeper - J4 PressureWatch (5分毎)
#   メモリプレッシャー / Load Avg / 圧縮メモリ / スワップを監視し、
#   閾値超過で通知を出す（自動対処はしない）

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=../lib/log.sh
source "$ROOT_DIR/lib/log.sh"
# shellcheck source=../lib/notify.sh
source "$ROOT_DIR/lib/notify.sh"
# shellcheck source=../config/thresholds.sh
source "$ROOT_DIR/config/thresholds.sh"

JOB="monitor"
COOLDOWN_FILE="$LOG_DIR/.monitor-cooldown"

# 直近通知からのクールダウン制御
should_notify() {
  local key="$1"
  local now
  now=$(date +%s)
  local last=0
  if [ -f "$COOLDOWN_FILE" ]; then
    last=$(grep "^$key:" "$COOLDOWN_FILE" 2>/dev/null | cut -d: -f2)
    last=${last:-0}
  fi
  local cooldown=$((NOTIFICATION_COOLDOWN_MIN * 60))
  if [ $((now - last)) -lt "$cooldown" ]; then
    return 1
  fi
  grep -v "^$key:" "$COOLDOWN_FILE" 2>/dev/null > "$COOLDOWN_FILE.tmp" || true
  echo "$key:$now" >> "$COOLDOWN_FILE.tmp"
  mv "$COOLDOWN_FILE.tmp" "$COOLDOWN_FILE"
  return 0
}

# --- メトリクス取得 ---

# スワップ使用量 (MB)
swap_used_mb=$(sysctl -n vm.swapusage 2>/dev/null | sed -E 's/.*used = ([0-9.]+)M.*/\1/' | awk '{printf "%d", $1}')
swap_used_mb=${swap_used_mb:-0}

# 圧縮メモリ (GB) — vm_stat の "Pages occupied by compressor" × 4KB
compressor_pages=$(vm_stat 2>/dev/null | awk '/Pages occupied by compressor/ {gsub("\\.",""); print $5}')
compressor_pages=${compressor_pages:-0}
compressed_gb=$(awk -v p="$compressor_pages" 'BEGIN { printf "%.1f", p * 4096 / 1024 / 1024 / 1024 }')

# Load Avg 1m
load_1m=$(uptime | sed -E 's/.*load averages?:?[[:space:]]+([0-9.]+).*/\1/' | awk '{printf "%.1f", $1}')
load_1m=${load_1m:-0}

# CPU コア数
ncpu=$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)
load_threshold=$((ncpu * THRESHOLD_LOAD_AVG_MULTIPLIER))

# メモリプレッシャー: "System-wide memory free percentage: X%" を読み取り、
#   < 10% = critical, < 25% = warn, それ以外 = normal
mem_pressure="normal"
free_pct=$(memory_pressure 2>/dev/null | awk -F': ' '/memory free percentage/ {gsub("%","",$2); print $2}')
free_pct=${free_pct:-100}
if [ "$free_pct" -lt 10 ] 2>/dev/null; then mem_pressure="critical"
elif [ "$free_pct" -lt 25 ] 2>/dev/null; then mem_pressure="warn"
fi

# --- 記録 ---
log "$JOB" "swap=${swap_used_mb}MB compressed=${compressed_gb}GB load1m=${load_1m} cores=${ncpu} pressure=${mem_pressure}"

# --- 判定 & 通知 ---

# 1) スワップ蓄積
if [ "$swap_used_mb" -ge "$THRESHOLD_SWAP_USED_MB" ]; then
  if should_notify "swap"; then
    notify "⚠️ Mac Health: スワップ蓄積" "${swap_used_mb}MB 使用中。重いアプリを Quit してください" "swap"
    log_event "$JOB" "WARN" "swap usage ${swap_used_mb}MB exceeded threshold ${THRESHOLD_SWAP_USED_MB}MB"
  fi
fi

# 2) 圧縮メモリ蓄積
compressed_int=$(awk -v g="$compressed_gb" 'BEGIN { printf "%d", g }')
if [ "$compressed_int" -ge "$THRESHOLD_COMPRESSED_GB" ]; then
  if should_notify "compressed"; then
    notify "⚠️ Mac Health: 圧縮メモリ" "${compressed_gb}GB に達しています。AppRefresh で軽くなります" "compressed"
    log_event "$JOB" "WARN" "compressed memory ${compressed_gb}GB exceeded threshold ${THRESHOLD_COMPRESSED_GB}GB"
  fi
fi

# 3) Load Avg
load_int=$(awk -v l="$load_1m" 'BEGIN { printf "%d", l }')
if [ "$load_int" -ge "$load_threshold" ]; then
  if should_notify "load"; then
    notify "⚠️ Mac Health: 高負荷" "Load Avg ${load_1m} (閾値 ${load_threshold})" "load"
    log_event "$JOB" "WARN" "load avg ${load_1m} exceeded threshold ${load_threshold}"
  fi
fi

# 4) メモリプレッシャー critical
if [ "$mem_pressure" = "critical" ]; then
  if should_notify "pressure"; then
    notify "🔥 Mac Health: メモリ圧迫 Critical" "重い Electron アプリを Quit してください" "pressure"
    log_event "$JOB" "WARN" "memory pressure critical"
  fi
fi

rotate_logs
exit 0
