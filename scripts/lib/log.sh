#!/bin/bash
# Mac Health Keeper - ログユーティリティ
LOG_DIR="$HOME/Library/Logs/MacHealth"
mkdir -p "$LOG_DIR"

# log <job> <message...>
log() {
  local job="$1"
  shift
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$ts] $*" >> "$LOG_DIR/$job.log"
}

# events.log: ユーザーに通知された出来事
log_event() {
  local job="$1"
  local level="$2"   # INFO / WARN / ACTION
  shift 2
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$ts] [$level] [$job] $*" >> "$LOG_DIR/events.log"
}

# 14日以上前のログを削除
rotate_logs() {
  find "$LOG_DIR" -name "*.log" -mtime +14 -delete 2>/dev/null
}
