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

# === 4.5 shallow clone ガード（CFBundleVersion fallback 警告）===
# issue: 20260529_123513_README_shallow_clone注意書き追加
# `git clone --depth=1` 等で shallow clone された環境では `version_stamp.sh` の
# `git describe --tags --always` が tag を見つけられず CFBundleVersion が `0.0.0-DEV`
# fallback に落ちる。ビルドより前に shallow を検出し、stderr に警告と推奨手順を出す。
# 環境変数 MACHEALTH_AUTO_UNSHALLOW=1 を指定された場合は `git fetch --tags --unshallow`
# を自動実行する。検出スクリプト側で常に exit 0 を返すため、ここではビルドを止めない。
echo ""
echo "▶ shallow clone ガード（CFBundleVersion fallback 警告）"
bash "$REPO_DIR/scripts/lib/shallow_clone_guard.sh" "$REPO_DIR" || true

# === 5. Swift ビルド & .app バンドル組立 ===
# issue: 20260529_122727_Makefile_app化拡張 §B.4 で `.app` 組み立てロジックを
# `scripts/lib/build_app_bundle.sh` に集約。本ブロックは内部で同スクリプトを
# 呼び、出力先 $APP_DIR (= ~/Applications/MacHealth.app) は維持する。
# CFBundleVersion の stamp も build_app_bundle.sh 内部で version_stamp.sh を
# 呼ぶことで完了する（旧 §5.5 ブロックは廃止し、build_app_bundle.sh に集約）。
echo ""
echo "▶ Swift ビルド"
cd "$INSTALL_DIR/src"
swiftc MacHealth.swift MetricsCollector.swift MenuBuilder.swift \
  "$REPO_DIR/Sources/MacHealthKit/ScheduleTiming.swift" \
  "$REPO_DIR/Sources/MacHealthKit/Metrics.swift" \
  "$REPO_DIR/Sources/MacHealthKit/JobCatalog.swift" \
  "$REPO_DIR/Sources/MacHealthKit/MetricsParser.swift" \
  "$REPO_DIR/Sources/MacHealthKit/MetricsCollectorPolicy.swift" \
  "$REPO_DIR/Sources/MacHealthKit/MenuModel.swift" \
  "$REPO_DIR/Sources/MacHealthKit/ShellRunner.swift" \
  "$REPO_DIR/Sources/MacHealthKit/AppleScriptEscaper.swift" \
  "$REPO_DIR/Sources/MacHealthKit/JobController.swift" \
  "$REPO_DIR/Sources/MacHealthKit/AppBundlePolicy.swift" \
  "$REPO_DIR/Sources/MacHealthKit/Version.swift" \
  -o MacHealth
echo "  ✅ ビルド完了 ($(ls -la MacHealth | awk '{print $5}') bytes)"

echo ""
echo "▶ .app バンドル組立 + stamp: $APP_DIR"
# 既存があれば一旦終了（旧 .app の MacOS バイナリを上書きするため）
osascript -e 'quit app "Mac Health"' 2>/dev/null || true
sleep 1
# build_app_bundle.sh が内部で:
#   - mkdir Contents/{MacOS,Resources}
#   - cp バイナリ・Info.plist
#   - version_stamp.sh で CFBundleVersion stamp（REPO_DIR=$REPO_DIR）
# を実行する。stdout に注入された CFBundleVersion を返す。
if stamped=$(bash "$REPO_DIR/scripts/lib/build_app_bundle.sh" \
  "$INSTALL_DIR/src/MacHealth" \
  "$INSTALL_DIR/src/Info.plist" \
  "$APP_DIR" \
  "$REPO_DIR"); then
  if [ -n "$stamped" ]; then
    echo "  ✅ 配置完了 (CFBundleVersion=$stamped)"
  else
    echo "  ✅ 配置完了"
  fi
else
  echo "  ❌ .app 組み立て失敗（build_app_bundle.sh 非 0 終了）"
  exit 1
fi

# === 6. LaunchAgent をロード ===
# issue: 20260529_122242_LaunchAgentロード失敗調査と修正
# 旧コード（`launchctl list | grep` 判定）は RunAtLoad=false な docker plist で偽陽性を出していた
# （memo/20260529_204726_root-cause-investigation.md §2）。
# scripts/lib/launchagent_lifecycle.sh の load_launchagent を使い、bootout → bootstrap → verify
# （launchctl print 経由）の冪等シーケンスに統一する。各 phase の stderr は構造化ログとして出力される。
echo ""
echo "▶ LaunchAgent をロード"
# shellcheck source=scripts/lib/launchagent_lifecycle.sh
source "$REPO_DIR/scripts/lib/launchagent_lifecycle.sh"
LA_FAIL=0
for job in "${JOBS[@]}"; do
  plist="$LAUNCH_AGENT_DIR/${BUNDLE_PREFIX}.${job}.plist"
  label="${BUNDLE_PREFIX}.${job}"
  # load_launchagent は 3 行の構造化ログ（label= phase= exit= stderr=）を stdout に出す。
  # サマリ上は短く済ませるため、構造化ログは indented でそのまま流す。
  if lifecycle_out=$(load_launchagent "$label" "$plist"); then
    echo "  ✅ $job loaded"
  else
    echo "  ⚠️  $job ロード失敗"
    LA_FAIL=$((LA_FAIL + 1))
  fi
  # 構造化ログを 2 スペース indent で表示（運用時のエラー原因追跡用）
  printf '%s\n' "$lifecycle_out" | sed 's/^/    /'
done
if [ "$LA_FAIL" -gt 0 ]; then
  echo ""
  echo "  ℹ️  $LA_FAIL 件のロード失敗あり。診断スクリプトで詳細確認:"
  echo "       bash $INSTALL_DIR/bin/launchagent-doctor.sh"
fi

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
