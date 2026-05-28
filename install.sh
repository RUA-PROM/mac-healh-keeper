#!/bin/bash
# Mac Health Keeper - インストーラ
# Usage: ./install.sh
#
# 何をするか:
#   1) macOS / Swift コンパイラのチェック
#   2) scripts/ を ~/.local/bin/mac-health/ にコピー
#   3) LaunchAgent plist のテンプレートを実体化して ~/Library/LaunchAgents/ に配置
#   4) Swift をビルドして ~/Applications/MacHealth.app を作成
#   5) launchctl で 4 つのジョブをロード
#   6) アプリを起動
#   7) ログイン項目に追加（自動起動）

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/.local/bin/mac-health"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
APP_DIR="$HOME/Applications/MacHealth.app"
LOG_DIR="$HOME/Library/Logs/MacHealth"

BUNDLE_PREFIX="com.github.adachi-tatsuru.machealth"
JOBS=("monitor" "docker" "uptime" "refresh")

echo "==========================================================="
echo " Mac Health Keeper - Install"
echo "==========================================================="

# === 1. 環境チェック ===
echo ""
echo "▶ 環境チェック"

if [[ "$OSTYPE" != darwin* ]]; then
  echo "  ❌ macOS 専用です ($OSTYPE)"
  exit 1
fi
echo "  ✅ macOS"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "  ❌ swiftc が見つかりません。先に 'xcode-select --install' を実行してください"
  exit 1
fi
echo "  ✅ swiftc ($(swiftc --version | head -1))"

if ! command -v osascript >/dev/null 2>&1; then
  echo "  ❌ osascript が見つかりません（macOS 標準のはず）"
  exit 1
fi
echo "  ✅ osascript"

# === 2. スクリプト類をコピー ===
echo ""
echo "▶ スクリプトを $INSTALL_DIR にコピー"
mkdir -p "$INSTALL_DIR"/{bin,lib,config,src}
cp -R "$REPO_DIR/scripts/bin/."    "$INSTALL_DIR/bin/"
cp -R "$REPO_DIR/scripts/lib/."    "$INSTALL_DIR/lib/"
cp -R "$REPO_DIR/scripts/config/." "$INSTALL_DIR/config/"
cp -R "$REPO_DIR/src/."            "$INSTALL_DIR/src/"
chmod +x "$INSTALL_DIR/bin/"*
echo "  ✅ コピー完了"

# === 3. LaunchAgent plist を実体化 ===
echo ""
echo "▶ LaunchAgent plist を $LAUNCH_AGENT_DIR に配置"
mkdir -p "$LAUNCH_AGENT_DIR"
for job in "${JOBS[@]}"; do
  template="$REPO_DIR/launchagents/${BUNDLE_PREFIX}.${job}.plist.template"
  dest="$LAUNCH_AGENT_DIR/${BUNDLE_PREFIX}.${job}.plist"
  sed "s|{{HOME}}|$HOME|g" "$template" > "$dest"
  echo "  ✅ $(basename "$dest")"
done

# === 4. ログディレクトリ準備 ===
mkdir -p "$LOG_DIR"

# === 5. Swift ビルド & .app バンドル組立 ===
echo ""
echo "▶ Swift ビルド"
cd "$INSTALL_DIR/src"
swiftc MacHealth.swift MetricsCollector.swift MenuBuilder.swift \
  "$REPO_DIR/Sources/MacHealthKit/ScheduleTiming.swift" \
  "$REPO_DIR/Sources/MacHealthKit/Metrics.swift" \
  "$REPO_DIR/Sources/MacHealthKit/JobCatalog.swift" \
  "$REPO_DIR/Sources/MacHealthKit/MetricsParser.swift" \
  "$REPO_DIR/Sources/MacHealthKit/MenuModel.swift" \
  "$REPO_DIR/Sources/MacHealthKit/ShellRunner.swift" \
  "$REPO_DIR/Sources/MacHealthKit/JobController.swift" \
  -o MacHealth
echo "  ✅ ビルド完了 ($(ls -la MacHealth | awk '{print $5}') bytes)"

echo ""
echo "▶ .app バンドル組立: $APP_DIR"
# 既存があれば一旦終了
osascript -e 'quit app "Mac Health"' 2>/dev/null || true
sleep 1
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp MacHealth  "$APP_DIR/Contents/MacOS/"
cp Info.plist "$APP_DIR/Contents/"
echo "  ✅ 配置完了"

# === 6. LaunchAgent をロード ===
echo ""
echo "▶ LaunchAgent をロード"
UID_NUM=$(id -u)
for job in "${JOBS[@]}"; do
  plist="$LAUNCH_AGENT_DIR/${BUNDLE_PREFIX}.${job}.plist"
  # 既存があれば一旦アンロード
  launchctl bootout "gui/$UID_NUM/${BUNDLE_PREFIX}.${job}" 2>/dev/null || true
  launchctl bootstrap "gui/$UID_NUM" "$plist" 2>/dev/null || launchctl load "$plist"
  if launchctl list | grep -q "${BUNDLE_PREFIX}.${job}"; then
    echo "  ✅ $job loaded"
  else
    echo "  ⚠️  $job ロード失敗"
  fi
done

# === 7. アプリを起動 ===
echo ""
echo "▶ Mac Health.app を起動"
open "$APP_DIR"
sleep 1
if pgrep -f "MacHealth.app/Contents/MacOS/MacHealth" >/dev/null; then
  echo "  ✅ 起動成功（メニューバーに 🩺/ステトスコープ アイコンが出るはず）"
else
  echo "  ⚠️  起動に失敗。手動で確認: open '$APP_DIR'"
fi

# === 8. ログイン項目に追加 ===
echo ""
echo "▶ ログイン項目に追加（自動起動）"
if osascript -e 'tell application "System Events" to get name of every login item' 2>/dev/null | grep -q "MacHealth"; then
  echo "  ✅ 既に登録済み"
else
  osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"$APP_DIR\", hidden:true}" >/dev/null 2>&1
  echo "  ✅ 追加完了"
fi

echo ""
echo "==========================================================="
echo " ✅ Mac Health Keeper のインストール完了！"
echo "==========================================================="
echo ""
echo "🩺 メニューバー右上のアイコンをクリックして使ってください"
echo ""
echo "  CLI:        $INSTALL_DIR/bin/mac-health status"
echo "  アプリ:     $APP_DIR"
echo "  ログ:       $LOG_DIR"
echo "  LaunchAgent: $LAUNCH_AGENT_DIR/${BUNDLE_PREFIX}.*.plist"
echo ""
echo "アンインストール: ./uninstall.sh"
echo ""
