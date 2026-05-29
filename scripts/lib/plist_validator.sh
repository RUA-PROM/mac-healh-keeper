#!/bin/bash
# Mac Health Keeper - plist 構文 + 必須キー検証ライブラリ
#
# issue: 20260529_122242_LaunchAgentロード失敗調査と修正
#
# `plutil -lint` による XML 構文検証に加え、LaunchAgent plist として最低限必須の
# キー（Label, ProgramArguments）が含まれていることを軽量に確認する。
# `make check` 経路で 4 plist テンプレを回帰検査するための pure 関数群（副作用なし・
# stdin/stdout のみ）。
#
# 使い方:
#   source scripts/lib/plist_validator.sh
#   validate_plist <file>           # 0=OK, 1=構文 NG, 2=必須キー NG
#
# 依存: bash, plutil（macOS 標準）, grep。set -e は呼び出し元に委ねる。

# validate_plist <file>
#   plist の構文と LaunchAgent 必須キーを確認する。
#   - 戻り値: 0=OK, 1=構文 NG（plutil -lint 失敗）, 2=必須キー欠落
#   - stdout には人間可読のメッセージを 1 行出す（成功時 "OK: <file>"）
validate_plist() {
  local file="$1"
  if [ -z "$file" ] || [ ! -f "$file" ]; then
    echo "NG: plist not found: ${file:-<empty>}"
    return 1
  fi

  # 構文検証
  if ! plutil -lint "$file" >/dev/null 2>&1; then
    echo "NG: plutil -lint failed: $file"
    return 1
  fi

  # 必須キー: Label
  if ! grep -q "<key>Label</key>" "$file"; then
    echo "NG: missing required key Label: $file"
    return 2
  fi

  # 必須キー: ProgramArguments
  if ! grep -q "<key>ProgramArguments</key>" "$file"; then
    echo "NG: missing required key ProgramArguments: $file"
    return 2
  fi

  echo "OK: $file"
  return 0
}
