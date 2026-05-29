#!/bin/bash
# Mac Health Keeper - LaunchAgent ライフサイクル管理ライブラリ
#
# issue: 20260529_122242_LaunchAgentロード失敗調査と修正
#
# bootout → bootstrap → verify（launchctl print 経由）の冪等シーケンスを集約する shell library。
# 既存 install.sh の verification は `launchctl list | grep` を使っており、RunAtLoad=false な
# docker plist で launchd internal list 反映タイミングに依存して偽陽性を出していた
# （memo/20260529_204726_root-cause-investigation.md §2）。本ライブラリはこれを
# `launchctl print` ベース判定に置換する。
#
# 使い方:
#   source scripts/lib/launchagent_lifecycle.sh
#   load_launchagent <label> <plist_path>           # 戻り値 0=success, 1=verify failure
#   verify_launchagent_loaded <label>               # 戻り値 0=loaded, 1=not loaded
#
# テスト用差し替え:
#   LAUNCHCTL_BIN=/path/to/fake_launchctl   # 実 launchctl を差し替え（mock）
#   LIFECYCLE_UID=12345                     # gui ドメインの UID を上書き
#
# 形式（stdout 構造化ログ）:
#   label=<label> phase=<bootout|bootstrap|verify> exit=<n> stderr=<excerpt>
# 1 関数呼び出しにつき最大 3 行（bootout/bootstrap/verify それぞれ 1 行）。
#
# 依存: bash, launchctl（mock 可能）。set -e は呼び出し元に委ねる（関数は終了コードで通知）。

# ==============================================================================
# 内部ヘルパ
# ==============================================================================

# launchctl 実体（mock 差し替え可能）
__lifecycle_launchctl() {
  "${LAUNCHCTL_BIN:-launchctl}" "$@"
}

# gui ドメインの UID（mock 差し替え可能）
__lifecycle_uid() {
  echo "${LIFECYCLE_UID:-$(id -u)}"
}

# stderr を最大 120 文字に切り詰める（改行は半角スペース化、構造化ログを 1 行に保つため）
__lifecycle_excerpt() {
  local s
  s=$(tr '\n\r' '  ' <"$1" 2>/dev/null || true)
  # 先頭末尾の空白除去
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  if [ ${#s} -gt 120 ]; then
    printf '%s' "${s:0:120}"
  else
    printf '%s' "$s"
  fi
}

# 構造化ログ 1 行を stdout に出す
__lifecycle_log() {
  local label="$1" phase="$2" exit_code="$3" stderr_excerpt="$4"
  printf 'label=%s phase=%s exit=%d stderr=%s\n' \
    "$label" "$phase" "$exit_code" "$stderr_excerpt"
}

# ==============================================================================
# 公開関数
# ==============================================================================

# verify_launchagent_loaded <label>
#   `launchctl print gui/<uid>/<label>` を実行し、出力に "Could not find service" を
#   含まなければ loaded と判定。`launchctl list` の偽陽性問題を回避する公式 API 経路。
#   戻り値: 0=loaded, 1=not loaded
verify_launchagent_loaded() {
  local label="$1"
  local uid; uid=$(__lifecycle_uid)
  local tmperr; tmperr=$(mktemp)
  local out
  out=$(__lifecycle_launchctl print "gui/$uid/$label" 2>"$tmperr") || true
  local rc=$?
  # exit 0 でも "Could not find service" を含む場合は not loaded（macOS の launchctl は
  # not-found を exit 非 0 + stderr に出すが念のため出力テキストも確認する）
  local merged="$out"
  if [ -s "$tmperr" ]; then
    merged="$merged"$'\n'"$(cat "$tmperr")"
  fi
  rm -f "$tmperr"
  if printf '%s' "$merged" | grep -q "Could not find service"; then
    return 1
  fi
  # 出力が空（または明らかにエラー）の場合は not loaded
  if [ -z "$out" ] && [ "$rc" -ne 0 ]; then
    return 1
  fi
  return 0
}

# load_launchagent <label> <plist_path>
#   冪等な bootout → bootstrap → verify シーケンスを実行する。
#   既ロード状態への bootstrap は launchctl の仕様で "Bootstrap failed: 5: Input/output error"
#   になるため、必ず bootout（idempotent）してから bootstrap する。
#   verify は verify_launchagent_loaded（launchctl print 経由）で判定する。
#
#   戻り値: 0=loaded（verify 成功）, 1=verify failure（bootout/bootstrap いずれかが失敗）
#   stdout: 構造化ログを 3 行（phase=bootout/bootstrap/verify）出力する。
load_launchagent() {
  local label="$1" plist="$2"
  local uid; uid=$(__lifecycle_uid)
  local tmperr; tmperr=$(mktemp)
  local rc

  # --- phase=bootout（idempotent: 未ロードでもエラーを致命とみなさない） ---
  __lifecycle_launchctl bootout "gui/$uid/$label" 2>"$tmperr"
  rc=$?
  __lifecycle_log "$label" "bootout" "$rc" "$(__lifecycle_excerpt "$tmperr")"

  # --- phase=bootstrap（成功必須） ---
  : >"$tmperr"
  __lifecycle_launchctl bootstrap "gui/$uid" "$plist" 2>"$tmperr"
  rc=$?
  __lifecycle_log "$label" "bootstrap" "$rc" "$(__lifecycle_excerpt "$tmperr")"
  if [ "$rc" -ne 0 ]; then
    rm -f "$tmperr"
    # bootstrap が失敗してもまだ verify は試行する（既ロード状態を bootout し損ねた等の救済）
    if verify_launchagent_loaded "$label"; then
      __lifecycle_log "$label" "verify" 0 "bootstrap-failed-but-verified-loaded"
      return 0
    fi
    __lifecycle_log "$label" "verify" 1 "bootstrap-failed-and-not-loaded"
    return 1
  fi

  # --- phase=verify（launchctl print 経由） ---
  rm -f "$tmperr"
  if verify_launchagent_loaded "$label"; then
    __lifecycle_log "$label" "verify" 0 ""
    return 0
  fi
  __lifecycle_log "$label" "verify" 1 "verify-print-could-not-find"
  return 1
}
