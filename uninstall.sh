#!/bin/bash
# Mac Health Keeper - アンインストーラ

set -u

INSTALL_DIR="$HOME/.local/bin/mac-health"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
APP_DIR="$HOME/Applications/MacHealth.app"
LOG_DIR="$HOME/Library/Logs/MacHealth"

BUNDLE_PREFIX="com.github.adachi-tatsuru.machealth"
JOBS=("monitor" "docker" "uptime" "refresh")

echo "==========================================================="
echo " Mac Health Keeper - Uninstall"
echo "==========================================================="

UID_NUM=$(id -u)

echo ""
echo "▶ LaunchAgent をアンロード & 削除"
for job in "${JOBS[@]}"; do
  label="${BUNDLE_PREFIX}.${job}"
  plist="$LAUNCH_AGENT_DIR/${label}.plist"
  launchctl bootout "gui/$UID_NUM/$label" 2>/dev/null || true
  launchctl unload "$plist" 2>/dev/null || true
  rm -f "$plist"
  echo "  - $label"
done

echo ""
echo "▶ アプリ Quit + 削除"
osascript -e 'quit app "Mac Health"' 2>/dev/null || true
pkill -f "MacHealth.app/Contents/MacOS/MacHealth" 2>/dev/null || true
rm -rf "$APP_DIR"
echo "  - $APP_DIR"

echo ""
echo "▶ ログイン項目から削除"
osascript -e 'tell application "System Events" to delete login item "MacHealth"' 2>/dev/null || true

echo ""
echo "▶ スクリプト類を削除"
rm -rf "$INSTALL_DIR"
echo "  - $INSTALL_DIR"

echo ""
echo "▶ ログ"
read -p "  ログ ($LOG_DIR) も削除しますか？ [y/N]: " yn
if [[ "$yn" =~ ^[Yy]$ ]]; then
  rm -rf "$LOG_DIR"
  echo "  - 削除しました"
else
  echo "  - 残しました"
fi

echo ""
echo "==========================================================="
echo " ✅ アンインストール完了"
echo "==========================================================="
