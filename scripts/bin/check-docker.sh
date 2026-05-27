#!/bin/bash
# Mac Health Keeper - J3 DockerIdleStop (10分毎)
#   Docker Desktop が起動 + コンテナ 0 の状態が一定時間続いたら、
#   業務時間外なら自動 Quit、業務時間内なら通知のみ。

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/lib/log.sh"
source "$ROOT_DIR/lib/notify.sh"
source "$ROOT_DIR/config/thresholds.sh"

JOB="docker"
STATE_FILE="$LOG_DIR/.docker-state"

# Docker Desktop が起動しているか
if ! pgrep -f "Docker Desktop.app/Contents/MacOS/Docker Desktop" > /dev/null 2>&1 \
   && ! pgrep -f "com.apple.Virtualization.VirtualMachine" > /dev/null 2>&1; then
  rm -f "$STATE_FILE"
  log "$JOB" "Docker not running"
  exit 0
fi

# コンテナ数を取得（socket が反応しない可能性も考慮、3秒タイムアウト）
container_count=$(
  # docker CLI で `--max-time` は無いので、バックグラウンド + kill で実装
  (docker ps -q 2>/dev/null | wc -l | tr -d ' ') &
  pid=$!
  ( sleep 3; kill -9 $pid 2>/dev/null ) &
  killer=$!
  wait $pid 2>/dev/null
  kill -9 $killer 2>/dev/null || true
)
container_count=${container_count:-unknown}

log "$JOB" "Docker running, containers=$container_count"

# コンテナがあるなら何もしない
if [ "$container_count" != "0" ]; then
  rm -f "$STATE_FILE"
  exit 0
fi

# コンテナ 0 が継続している時間を計測
now=$(date +%s)
if [ -f "$STATE_FILE" ]; then
  since=$(cat "$STATE_FILE")
else
  since="$now"
  echo "$since" > "$STATE_FILE"
fi
elapsed_min=$(( (now - since) / 60 ))

log "$JOB" "idle for ${elapsed_min} min"

# 猶予期間内なら何もしない
if [ "$elapsed_min" -lt "$DOCKER_IDLE_GRACE_MINUTES" ]; then
  exit 0
fi

# 業務時間外 → 自動 Quit
if ! is_business_hours; then
  osascript -e 'quit app "Docker Desktop"' 2>/dev/null
  notify "🧹 Mac Health: Docker を整理" "コンテナなしで ${elapsed_min} 分経過 → 自動 Quit"
  log_event "$JOB" "ACTION" "auto-quit Docker Desktop (idle ${elapsed_min} min, off-hours)"
  rm -f "$STATE_FILE"
  exit 0
fi

# 業務時間内 → 通知のみ（クールダウン 6 時間）
COOLDOWN_FILE="$LOG_DIR/.docker-notify-cooldown"
last=0
if [ -f "$COOLDOWN_FILE" ]; then last=$(cat "$COOLDOWN_FILE"); fi
if [ $((now - last)) -ge 21600 ]; then
  notify "💡 Mac Health: Docker アイドル" "コンテナなしで ${elapsed_min} 分。使用しなければ Quit 推奨"
  echo "$now" > "$COOLDOWN_FILE"
  log_event "$JOB" "INFO" "docker idle ${elapsed_min} min during business hours (notify only)"
fi

exit 0
