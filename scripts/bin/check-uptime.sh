#!/bin/bash
# Mac Health Keeper - J5 UptimeNudge (毎日 09:00)
#   uptime が一定日数を超えたら控えめに通知。

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/lib/log.sh"
source "$ROOT_DIR/lib/notify.sh"
source "$ROOT_DIR/config/thresholds.sh"

JOB="uptime"

# 全ジョブ共通の終了処理（ローテート）を確実に呼ぶ（02 §3.3。L2 是正）。
trap 'finalize_job "$JOB"' EXIT

# 起動からの経過秒数
# 注: sed で ".*sec" は "usec" にもマッチするので awk で第4列を取る
boot_time=$(sysctl -n kern.boottime | awk '{print $4}' | tr -d ',')
now=$(date +%s)
elapsed_sec=$((now - boot_time))
elapsed_days=$((elapsed_sec / 86400))

log "$JOB" "uptime=${elapsed_days}days"

if [ "$elapsed_days" -ge "$UPTIME_WARN_DAYS" ]; then
  notify "💡 Mac Health: 長期稼働中" "${elapsed_days}日連続起動。月1回程度の再起動推奨"
  log_event "$JOB" "INFO" "uptime ${elapsed_days} days exceeded ${UPTIME_WARN_DAYS}"
fi

exit 0
