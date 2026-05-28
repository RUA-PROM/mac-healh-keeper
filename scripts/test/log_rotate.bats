#!/usr/bin/env bats
# Mac Health Keeper - ログローテート（log.sh / lock.sh）の単体テスト
# BDD 形式（ユースケース → シナリオ → Given/When/Then）は .agents/TEST_BDD_FORMAT.md に従う。
# 01 BDD UC1〜UC4 と 03 §2.2.4〜§2.7.4 のテスト仕様に 1 対 1 対応する。
# すべて一時 LOG_DIR・固定入力で副作用ゼロ（$HOME/Library/Logs/MacHealth を汚さない）。
#
# ユースケース: 追記ログをサイズ世代でローテートし、out/err も対象化し、並行更新を直列化し、失敗を可視化する。

setup() {
  TMP="$(mktemp -d)"
  export HOME="$TMP"   # log.sh の LOG_DIR 既定を一時領域に向け、実ログを汚さない
  export LOG_DIR="$TMP/logdir"; mkdir -p "$LOG_DIR/.locks"
  source "${BATS_TEST_DIRNAME}/../lib/lock.sh"
  source "${BATS_TEST_DIRNAME}/../lib/log.sh"
  export LOG_DIR   # log.sh の source で上書きされるため再設定
  LOG_DIR="$TMP/logdir"
}
teardown() { chmod -R 755 "$TMP" 2>/dev/null || true; rm -rf "$TMP"; }

# --- UC1 サイズ超過ローテート ---

# シナリオ: monitor.log が上限を超えると世代退避され本体が小さくなる（01 UC1-S1）。
@test "UC1-S1: rotate_logs backs up over-limit monitor.log to .1 and shrinks body" {
  # Given: 上限 100B に対し 200B の monitor.log
  export MHK_ROTATE_MAX_BYTES=100; export MHK_ROTATE_KEEP_GENERATIONS=3
  head -c 200 /dev/zero | tr '\0' 'a' > "$LOG_DIR/monitor.log"
  # When: rotate_logs を実行
  rotate_logs
  # Then: 本体は上限以下になり、.1 が生成される
  [ "$(file_size_bytes "$LOG_DIR/monitor.log")" -le 100 ]
  [ -f "$LOG_DIR/monitor.log.1" ]
}

# シナリオ: 上限未満なら何もしない（01 UC1-S2）。
@test "UC1-S2: rotate_logs leaves under-limit monitor.log unchanged" {
  # Given: 上限 1000B に対し 50B の monitor.log
  export MHK_ROTATE_MAX_BYTES=1000
  head -c 50 /dev/zero | tr '\0' 'a' > "$LOG_DIR/monitor.log"
  before=$(file_size_bytes "$LOG_DIR/monitor.log")
  # When: rotate_logs を実行
  rotate_logs
  # Then: サイズ不変・退避なし
  [ "$(file_size_bytes "$LOG_DIR/monitor.log")" -eq "$before" ]
  [ ! -f "$LOG_DIR/monitor.log.1" ]
}

# --- UC2 out/err の対象化 ---

# シナリオ: 上限超過の .err が切り詰め/退避され、対象外拡張子は不変（01 UC2-S1）。
@test "UC2-S1: rotate_logs rotates over-limit .err but leaves .txt untouched" {
  # Given: 上限 100B に対し 300B の launchd.monitor.err と対象外の note.txt
  export MHK_ROTATE_MAX_BYTES=100; export MHK_ROTATE_EXTS="log out err"
  head -c 300 /dev/zero | tr '\0' 'a' > "$LOG_DIR/launchd.monitor.err"
  head -c 300 /dev/zero | tr '\0' 'a' > "$LOG_DIR/note.txt"
  # When: rotate_logs を実行
  rotate_logs
  # Then: .err は上限以下、対象外の .txt は不変
  [ "$(file_size_bytes "$LOG_DIR/launchd.monitor.err")" -le 100 ]
  [ "$(file_size_bytes "$LOG_DIR/note.txt")" -eq 300 ]
}

# --- UC3 排他制御 ---

# シナリオ: 2 サブシェルが同時に cooldown を with_lock 下で更新しても記録が壊れない（01 UC3-S1）。
@test "UC3-S1: concurrent with_lock cooldown updates keep file uncorrupted" {
  # Given: 一時 LOG_DIR/.locks と COOLDOWN_FILE、with_lock 下のインクリメント関数
  export COOLDOWN_FILE="$TMP/cd"; : > "$COOLDOWN_FILE"
  append_line() { with_lock notify-cooldown bash -c 'grep -v "^k:" "$COOLDOWN_FILE" > "$COOLDOWN_FILE.tmp" 2>/dev/null || true; echo "k:$(date +%s)" >> "$COOLDOWN_FILE.tmp"; mv "$COOLDOWN_FILE.tmp" "$COOLDOWN_FILE"'; }
  export -f append_line with_lock acquire_lock release_lock _lock_base_dir
  # When: 2 サブシェルを並行起動し両方の完了を待つ
  ( append_line ) & p1=$!
  ( append_line ) & p2=$!
  wait "$p1"; wait "$p2"
  # Then: COOLDOWN_FILE は key:epoch 形式の行のみ・tmp 残骸なし（破損なし）
  grep -qE "^k:[0-9]+$" "$COOLDOWN_FILE"
  [ ! -e "$COOLDOWN_FILE.tmp" ]
}

# --- UC4 失敗の可視化 ---

# シナリオ: 書き込み失敗時にエラーを記録し沈黙せず処理を継続する（01 UC4-S1）。
@test "UC4-S1: rotate_logs records error to rotate.err on mv failure and continues" {
  # Given: 上限超の monitor.log を持つ LOG_DIR を読み取り専用にし、記録先は別の書込可ディレクトリ
  if [ "$(id -u)" -eq 0 ]; then skip "root では chmod 555 が効かないため代替手段で別途検証"; fi
  export MHK_ROTATE_MAX_BYTES=100
  head -c 300 /dev/zero | tr '\0' 'a' > "$LOG_DIR/monitor.log"
  ERR_DIR="$TMP/errout"; mkdir -p "$ERR_DIR"; export ROTATE_ERR_FILE="$ERR_DIR/rotate.err"
  chmod 555 "$LOG_DIR"
  # When: rotate_logs を実行（失敗しても継続）
  run rotate_logs
  chmod 755 "$LOG_DIR"
  # Then: 非 0 で落ちず、rotate.err にエラーが記録される
  [ "$status" -eq 0 ]
  grep -qE "\[ERROR\] \[rotate\]" "$ROTATE_ERR_FILE"
}

# --- 共通終了処理（冪等） ---

# シナリオ: finalize_job を 2 回呼んでも安全（冪等）（03 §2.4.4）。
@test "finalize_job is idempotent and keeps body under limit" {
  # Given: 上限超の monitor.log
  export MHK_ROTATE_MAX_BYTES=100
  head -c 300 /dev/zero | tr '\0' 'a' > "$LOG_DIR/monitor.log"
  # When: finalize_job を 2 回呼ぶ
  finalize_job monitor
  run finalize_job monitor
  # Then: 正常終了し本体は上限以下
  [ "$status" -eq 0 ]
  [ "$(file_size_bytes "$LOG_DIR/monitor.log")" -le 100 ]
}
