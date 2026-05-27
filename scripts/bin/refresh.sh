#!/bin/bash
# Mac Health Keeper - J1 AppRefresh (毎日 03:00)
#   メモリリークしやすい Electron アプリを順次 Quit → 再起動。
#   対象: Slack / Chatwork / Google Chrome / Firefox / Claude
#   除外: Cursor（編集中ファイルへの影響を避けるため）

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/lib/log.sh"
source "$ROOT_DIR/lib/notify.sh"

JOB="refresh"

# 対象アプリ（順序はメモリリークしやすい順）
APPS=(
  "Slack"
  "Chatwork"
  "Google Chrome"
  "Firefox"
  "Claude"
)

# 起動中か判定（プロセス名でゆるくマッチ）
is_running() {
  local app="$1"
  osascript -e "tell application \"System Events\" to (name of processes) contains \"$app\"" 2>/dev/null | grep -q "true"
}

# Quit を試みる（dirty 未保存があればスキップ）
quit_app() {
  local app="$1"
  # AppleScript で quit。アプリ側で保存ダイアログが出る場合は応答せず諦める。
  # `with timeout` で 15 秒待ち、保存待ちでハングするなら諦める。
  local result
  result=$(osascript <<APPLESCRIPT 2>&1
with timeout of 15 seconds
  try
    tell application "$app"
      quit saving no
    end tell
    return "ok"
  on error errMsg number errNum
    return "error: " & errMsg
  end try
end timeout
APPLESCRIPT
  )
  if [[ "$result" == "ok" ]]; then
    return 0
  else
    log "$JOB" "  quit failed for $app: $result"
    return 1
  fi
}

# プロセスが完全に消えるまで待機
wait_for_quit() {
  local app="$1"
  local max_wait=30
  local waited=0
  while is_running "$app" && [ "$waited" -lt "$max_wait" ]; do
    sleep 1
    waited=$((waited + 1))
  done
  if is_running "$app"; then
    return 1
  fi
  return 0
}

# 1 アプリのリフレッシュ
refresh_app() {
  local app="$1"
  if ! is_running "$app"; then
    log "$JOB" "$app: not running, skip"
    return 0
  fi

  log "$JOB" "$app: quitting..."
  if ! quit_app "$app"; then
    log_event "$JOB" "WARN" "$app: quit returned error (likely dirty), skip"
    return 1
  fi

  if ! wait_for_quit "$app"; then
    log_event "$JOB" "WARN" "$app: did not quit within timeout, force-skip relaunch"
    return 1
  fi

  log "$JOB" "$app: quit ok, relaunching..."
  open -a "$app" 2>/dev/null
  sleep 8
  log_event "$JOB" "ACTION" "$app: refreshed"
  return 0
}

# === main ===
log "$JOB" "=== AppRefresh start ==="

refreshed=0
skipped=0
for app in "${APPS[@]}"; do
  if refresh_app "$app"; then
    refreshed=$((refreshed + 1))
  else
    skipped=$((skipped + 1))
  fi
  sleep 5
done

log "$JOB" "=== AppRefresh done: refreshed=$refreshed skipped=$skipped ==="
notify "🌙 Mac Health: AppRefresh 完了" "${refreshed} 個を再起動 / ${skipped} 個スキップ"
log_event "$JOB" "INFO" "AppRefresh completed: refreshed=$refreshed skipped=$skipped"

rotate_logs
exit 0
