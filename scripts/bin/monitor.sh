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
# shellcheck source=../lib/metrics.sh
source "$ROOT_DIR/lib/metrics.sh"
# shellcheck source=./notification_cooldown.sh
source "$SCRIPT_DIR/notification_cooldown.sh"

JOB="monitor"
COOLDOWN_FILE="$LOG_DIR/.monitor-cooldown"

# クールダウン制御（should_notify）・閾値判定（exceeds_threshold / classify_pressure）は
# notification_cooldown.sh に分離（テスト対象）。挙動・key:epoch 形式は不変。

# --- メトリクス取得 ---
# 生メトリクスの取得は lib/metrics.sh に集約（判定/通知/ログは本ファイルの責務）。

# スワップ使用量 (MB)
swap_used_mb=$(metrics_swap_used_mb)
swap_used_mb=${swap_used_mb:-0}

# 圧縮メモリ (GB) — vm_stat の "Pages occupied by compressor" × 4KB
compressed_gb=$(metrics_compressed_gb)

# Load Avg 1m
load_1m=$(metrics_load_1m)
load_1m=${load_1m:-0}

# CPU コア数
ncpu=$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)
load_threshold=$((ncpu * THRESHOLD_LOAD_AVG_MULTIPLIER))

# メモリプレッシャー: "System-wide memory free percentage: X%" を読み取り、
#   < 10% = critical, < 25% = warn, それ以外 = normal
free_pct=$(metrics_memory_free_pct)
free_pct=${free_pct:-100}
mem_pressure=$(classify_pressure "$free_pct")

# --- 記録 ---
log "$JOB" "swap=${swap_used_mb}MB compressed=${compressed_gb}GB load1m=${load_1m} cores=${ncpu} pressure=${mem_pressure}"

# --- 判定 & 通知 ---

# 1) スワップ蓄積
if exceeds_threshold "$swap_used_mb" "$THRESHOLD_SWAP_USED_MB"; then
  if should_notify "swap"; then
    notify "⚠️ Mac Health: スワップ蓄積" "${swap_used_mb}MB 使用中。重いアプリを Quit してください" "swap"
    log_event "$JOB" "WARN" "swap usage ${swap_used_mb}MB exceeded threshold ${THRESHOLD_SWAP_USED_MB}MB"
  fi
fi

# 2) 圧縮メモリ蓄積
compressed_int=$(awk -v g="$compressed_gb" 'BEGIN { printf "%d", g }')
if exceeds_threshold "$compressed_int" "$THRESHOLD_COMPRESSED_GB"; then
  if should_notify "compressed"; then
    notify "⚠️ Mac Health: 圧縮メモリ" "${compressed_gb}GB に達しています。AppRefresh で軽くなります" "compressed"
    log_event "$JOB" "WARN" "compressed memory ${compressed_gb}GB exceeded threshold ${THRESHOLD_COMPRESSED_GB}GB"
  fi
fi

# 3) Load Avg
load_int=$(awk -v l="$load_1m" 'BEGIN { printf "%d", l }')
if exceeds_threshold "$load_int" "$load_threshold"; then
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
