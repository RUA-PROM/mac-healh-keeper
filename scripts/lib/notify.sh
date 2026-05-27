#!/bin/bash
# Mac Health Keeper - 通知ユーティリティ

# notify <title> <message> [subtitle]
notify() {
  local title="${1:-Mac Health}"
  local message="${2:-}"
  local subtitle="${3:-}"
  # AppleScript で通知センターに表示
  if [ -n "$subtitle" ]; then
    osascript -e "display notification \"$message\" with title \"$title\" subtitle \"$subtitle\"" 2>/dev/null
  else
    osascript -e "display notification \"$message\" with title \"$title\"" 2>/dev/null
  fi
}

# is_business_hours: 08:00 〜 22:00 を業務時間と判定
is_business_hours() {
  local hour
  hour=$(date '+%H')
  hour=$((10#$hour))
  if [ "$hour" -ge 8 ] && [ "$hour" -lt 22 ]; then
    return 0
  else
    return 1
  fi
}
