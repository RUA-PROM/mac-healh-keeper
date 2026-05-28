#!/bin/bash
# Mac Health Keeper - 排他制御（mkdir ベースのロック・source 用）
#
# macOS に flock が標準で無いため、mkdir の原子性を利用したロックを提供する。
# ロックは $LOG_DIR/.locks/<name>.lock を mkdir で作り、rmdir で解放する固定パス方式。
# /tmp の予測可能名や他ユーザー書込可能領域を避ける（02 §3.4 / §8.2）。
#
# 直列化対象: ① rotate_file の世代シフト ② should_notify の cooldown read-modify-write。
# 可用性方針（01 §3.4）: ロック取得に失敗してもジョブ本体は止めない（ベストエフォート + 記録）。
# フォールバック: LOG_DIR 未設定時もロックなしで従来動作する。

# ロックを格納するベースディレクトリを返す（LOG_DIR 未設定なら空）。
_lock_base_dir() {
  if [ -n "${LOG_DIR:-}" ]; then
    echo "$LOG_DIR/.locks"
  fi
}

# acquire_lock <name> [timeout_sec]
#   mkdir "$LOG_DIR/.locks/<name>.lock" を試行。timeout 秒リトライしても取得不可なら 1。
#   成功 0 / 失敗 1（ベストエフォート）。LOG_DIR 未設定時は 1（取得不可）を返す。
acquire_lock() {
  local name="$1"
  local timeout="${2:-${MHK_LOCK_TIMEOUT_SEC:-5}}"
  local base
  base="$(_lock_base_dir)"
  [ -z "$base" ] && return 1
  mkdir -p "$base" 2>/dev/null || return 1
  local lock="$base/$name.lock"
  local waited=0
  while ! mkdir "$lock" 2>/dev/null; do
    if [ "$waited" -ge "$timeout" ]; then
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
  return 0
}

# release_lock <name>
#   rmdir で解放する。存在しなくてもエラーにしない。
release_lock() {
  local name="$1"
  local base
  base="$(_lock_base_dir)"
  [ -z "$base" ] && return 0
  rmdir "$base/$name.lock" 2>/dev/null || true
  return 0
}

# with_lock <name> <command...>
#   取得 → command 実行 → 必ず解放。command の終了コードをそのまま返す。
#   取得失敗時はロックなしで command を実行し、失敗を記録（ジョブ本体は継続: 01 §3.4）。
with_lock() {
  local name="$1"
  shift
  local status
  if acquire_lock "$name"; then
    "$@"
    status=$?
    release_lock "$name"
    return "$status"
  fi
  # 取得失敗: ベストエフォートでロックなし実行し、記録する（record_rotation_error があれば使う）。
  if command -v record_rotation_error >/dev/null 2>&1; then
    record_rotation_error "$name.lock" "lock acquisition failed; proceeding without lock"
  fi
  "$@"
  return $?
}
