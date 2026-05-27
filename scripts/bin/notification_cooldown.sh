#!/bin/bash
# Mac Health Keeper - 通知クールダウン / 閾値判定（純粋ロジック・source 用）
#
# メトリクス取得（vm_stat / sysctl / memory_pressure 等）から分離した判定関数群。
# monitor.sh から source して使い、テスト（monitor.bats / monitor_test.sh）からも
# 同じ関数を source して固定入力で検証する。
#
# 入力はすべて引数または環境変数（COOLDOWN_FILE / NOTIFICATION_COOLDOWN_MIN）で受け取り、
# 外部コマンド・実ファイル($LOG_DIR)・実通知には依存しない。
# 分岐ロジック・key:epoch 形式・戻り値は monitor.sh 原文（L20-37 / L63-65 / L73-91）を維持する。

# 直近通知からのクールダウン制御（monitor.sh L20-37 と同一挙動）
#   入力: $1=key、環境変数 COOLDOWN_FILE / NOTIFICATION_COOLDOWN_MIN
#   出力: 戻り値 1=非通知（未経過）、0=通知（経過）。0 のとき COOLDOWN_FILE を key:now で更新。
should_notify() {
  local key="$1"
  local now
  now=$(date +%s)
  local last=0
  if [ -f "$COOLDOWN_FILE" ]; then
    last=$(grep "^$key:" "$COOLDOWN_FILE" 2>/dev/null | cut -d: -f2)
    last=${last:-0}
  fi
  local cooldown=$((NOTIFICATION_COOLDOWN_MIN * 60))
  if [ $((now - last)) -lt "$cooldown" ]; then
    return 1
  fi
  grep -v "^$key:" "$COOLDOWN_FILE" 2>/dev/null > "$COOLDOWN_FILE.tmp" || true
  echo "$key:$now" >> "$COOLDOWN_FILE.tmp"
  mv "$COOLDOWN_FILE.tmp" "$COOLDOWN_FILE"
  return 0
}

# 整数の閾値判定（monitor.sh L73/82/91 の `-ge` と同一）
#   入力: $1=value、$2=threshold（いずれも整数）
#   出力: 戻り値 0=真（value >= threshold）、1=偽
exceeds_threshold() {
  local value="$1"
  local threshold="$2"
  if [ "$value" -ge "$threshold" ]; then
    return 0
  fi
  return 1
}

# メモリプレッシャー分類（monitor.sh L63-65 と同一）
#   入力: $1=free_pct（整数）
#   出力: 標準出力に critical / warn / normal
classify_pressure() {
  local free_pct="$1"
  local mem_pressure="normal"
  if [ "$free_pct" -lt 10 ] 2>/dev/null; then
    mem_pressure="critical"
  elif [ "$free_pct" -lt 25 ] 2>/dev/null; then
    mem_pressure="warn"
  fi
  echo "$mem_pressure"
}
