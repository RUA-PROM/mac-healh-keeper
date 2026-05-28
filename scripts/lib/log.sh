#!/bin/bash
# Mac Health Keeper - ログユーティリティ
#
# ログ書込（log / log_event）に加え、サイズ世代ローテート（rotate_logs / rotate_file）と
# 全ジョブ共通の終了処理（finalize_job）を提供する。
# 判定（純粋関数: needs_rotation / next_generation）と実 I/O（rotate_file / rotate_logs）を
# 分離する Functional Core / Imperative Shell（02 §2.2）。
#
# 既存挙動は不変: ログ出力先 $LOG_DIR・書式 `[ts] ...` / `[ts] [level] [job] ...`。

LOG_DIR="$HOME/Library/Logs/MacHealth"
mkdir -p "$LOG_DIR"

# 排他制御（mkdir ベース）。ガード付き source（テスト・再 source 安全）。
if ! command -v with_lock >/dev/null 2>&1; then
  _LOG_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=./lock.sh
  source "$_LOG_SH_DIR/lock.sh"
fi

# log <job> <message...>
log() {
  local job="$1"
  shift
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$ts] $*" >> "$LOG_DIR/$job.log"
}

# events.log: ユーザーに通知された出来事
log_event() {
  local job="$1"
  local level="$2"   # INFO / WARN / ACTION
  shift 2
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$ts] [$level] [$job] $*" >> "$LOG_DIR/events.log"
}

# --- ローテート設定のフォールバック既定値（thresholds.sh 未 source 時も動作） ---
_rotate_max_bytes()   { echo "${MHK_ROTATE_MAX_BYTES:-5242880}"; }
_rotate_keep_gens()   { echo "${MHK_ROTATE_KEEP_GENERATIONS:-3}"; }
_rotate_exts()        { echo "${MHK_ROTATE_EXTS:-log out err}"; }
_rotate_err_file()    { echo "${ROTATE_ERR_FILE:-$LOG_DIR/rotate.err}"; }

# ===== Functional Core（純粋関数・実 I/O 非依存・テスト対象） =====

# needs_rotation <size> <limit>
#   size >= limit で 0（要ローテート）、未満で 1（不要）。非数値は不要扱い（1）。
needs_rotation() {
  local size="$1" limit="$2"
  case "$size$limit" in
    *[!0-9]*) return 1 ;;
  esac
  [ "$size" -ge "$limit" ] && return 0
  return 1
}

# next_generation <existing_max>
#   現存する最大世代番号を受け取り、次に使う世代番号（最大+1、なければ 1）を標準出力に返す。
#   純粋関数（実ファイルに触れない）。入力は呼び出し側が算出した現存世代の最大値。
next_generation() {
  local existing_max="${1:-0}"
  case "$existing_max" in
    *[!0-9]*) existing_max=0 ;;
  esac
  echo $((existing_max + 1))
}

# ===== Imperative Shell（実 I/O） =====

# file_size_bytes <path>
#   ファイルのバイト数を返す（存在しなければ 0）。薄い I/O ラッパ（macOS: stat -f%z）。
file_size_bytes() {
  local path="$1"
  if [ -f "$path" ]; then
    stat -f%z "$path" 2>/dev/null || echo 0
  else
    echo 0
  fi
}

# record_rotation_error <file> <reason>
#   ローテート失敗を握り潰さず記録する（L5 是正）。再帰回避のため rotate.err と stderr に書く。
#   rotate.err 自体の書込が失敗しても stderr には必ず出る。
record_rotation_error() {
  local file="$1" reason="$2"
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  local line="[$ts] [ERROR] [rotate] $file: $reason"
  echo "$line" >&2
  local err_file
  err_file="$(_rotate_err_file)"
  echo "$line" >> "$err_file" 2>/dev/null || true
}

# 現存する <base>.<n> の最大世代番号を返す（無ければ 0）。
_max_existing_generation() {
  local base="$1"
  local max=0 g n
  for g in "$base".[0-9]*; do
    [ -e "$g" ] || continue
    n="${g##*.}"
    case "$n" in
      ''|*[!0-9]*) continue ;;
    esac
    [ "$n" -gt "$max" ] && max="$n"
  done
  echo "$max"
}

# rotate_file <path>
#   1 ファイルを世代退避し本体を新規化（ロック下・原子的 mv）。
#   - 通常ログ（.log 等）: 世代シフト（大番号→小番号 mv）→ 本体 mv .1 → touch 新規化。
#   - launchd 出力（.out / .err）: 退避後の本体は launchd が開いたままの fd を保つため
#     原子的 truncate（cp で .1 退避 → `: > file`）にする（02 §3.2.3）。
#   各 I/O 失敗で record_rotation_error を呼び処理は継続。世代上限超過分は削除。
rotate_file() {
  with_lock rotate _rotate_file_locked "$1"
}

_rotate_file_locked() {
  local path="$1"
  local keep ext
  keep="$(_rotate_keep_gens)"
  ext="${path##*.}"

  # 1) 世代シフト（大きい番号から）: .keep を破棄し .n -> .n+1
  rm -f "$path.$((keep + 1))" 2>/dev/null || true
  local n
  for ((n = keep; n >= 1; n--)); do
    if [ -e "$path.$n" ]; then
      if ! mv -f "$path.$n" "$path.$((n + 1))" 2>/dev/null; then
        record_rotation_error "$path.$n" "generation shift failed (mv .$n -> .$((n + 1)))"
      fi
    fi
  done
  # 世代上限超過分（.keep+1 以降）を削除
  local g num
  for g in "$path".[0-9]*; do
    [ -e "$g" ] || continue
    num="${g##*.}"
    case "$num" in
      ''|*[!0-9]*) continue ;;
    esac
    if [ "$num" -gt "$keep" ]; then
      rm -f "$g" 2>/dev/null || true
    fi
  done

  # 2) 本体を退避し新規化
  case "$ext" in
    out|err)
      # launchd が開いたままの fd を保つため、コピー退避 + 原子的 truncate。
      if ! cp "$path" "$path.1" 2>/dev/null; then
        record_rotation_error "$path" "backup copy to .1 failed"
      fi
      if ! : > "$path" 2>/dev/null; then
        record_rotation_error "$path" "truncate failed"
      fi
      ;;
    *)
      # 通常ログ: 原子的 mv で退避 → 新規空ファイル。
      if mv "$path" "$path.1" 2>/dev/null; then
        if ! touch "$path" 2>/dev/null; then
          record_rotation_error "$path" "touch after rotate failed"
        fi
      else
        record_rotation_error "$path" "rotate (mv to .1) failed"
      fi
      ;;
  esac
  return 0
}

# rotate_logs
#   MHK_ROTATE_EXTS の各拡張子について LOG_DIR 直下を走査し、上限超過分を rotate_file する。
#   現 L26-28 の mtime+削除（find -mtime +14 -delete）を破壊的に置換（02 §3.1）。
#   失敗しても非 0 で落ちず継続する（record_rotation_error に記録）。
rotate_logs() {
  local limit ext f size
  limit="$(_rotate_max_bytes)"
  for ext in $(_rotate_exts); do
    for f in "$LOG_DIR"/*."$ext"; do
      [ -f "$f" ] || continue
      # 世代ファイル（monitor.log.1 等）は *.log にマッチしないため自然に対象外。
      size="$(file_size_bytes "$f")"
      if needs_rotation "$size" "$limit"; then
        rotate_file "$f"
      fi
    done
  done
  return 0
}

# finalize_job <job>
#   全ジョブ共通の終了処理（02 §3.3）。ローテートを確実に呼ぶ。冪等（要否判定後に退避）。
#   各ジョブが trap 'finalize_job "$JOB"' EXIT で配線する。
finalize_job() {
  rotate_logs
  return 0
}
