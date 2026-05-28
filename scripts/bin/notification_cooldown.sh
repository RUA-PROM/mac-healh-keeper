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

# 排他制御（with_lock）。ガード付き source（テスト・再 source 安全）。
# lock.sh 不在時は with_lock 未定義のままだが should_notify 側でフォールバックする。
if ! command -v with_lock >/dev/null 2>&1; then
  _NC_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [ -f "$_NC_SH_DIR/../lib/lock.sh" ]; then
    # shellcheck source=../lib/lock.sh
    source "$_NC_SH_DIR/../lib/lock.sh"
  fi
fi

# 直近通知からのクールダウン制御（monitor.sh L20-37 と同一挙動）
#   入力: $1=key、環境変数 COOLDOWN_FILE / NOTIFICATION_COOLDOWN_MIN
#   出力: 戻り値 1=非通知（未経過）、0=通知（経過）。0 のとき COOLDOWN_FILE を key:now で更新。
#   D 差分: cooldown 更新（read-modify-write）区間のみ with_lock で直列化（判定・形式・戻り値は不変）。
#   with_lock 不在時（lock.sh 未 source）はロックなしで従来動作にフォールバックする。
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
  if command -v with_lock >/dev/null 2>&1; then
    with_lock notify-cooldown _should_notify_update "$key" "$now"
  else
    _should_notify_update "$key" "$now"
  fi
  return 0
}

# cooldown ファイルの read-modify-write 本体（with_lock で直列化される区間）。
# 原文の挙動（key:epoch 形式・tmp 経由の原子的 mv）を維持する。
_should_notify_update() {
  local key="$1" now="$2"
  grep -v "^$key:" "$COOLDOWN_FILE" 2>/dev/null > "$COOLDOWN_FILE.tmp" || true
  echo "$key:$now" >> "$COOLDOWN_FILE.tmp"
  mv "$COOLDOWN_FILE.tmp" "$COOLDOWN_FILE"
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
