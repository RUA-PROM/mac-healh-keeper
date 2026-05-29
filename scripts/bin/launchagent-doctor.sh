#!/bin/bash
# Mac Health Keeper - LaunchAgent 診断スクリプト
#
# issue: 20260529_122242_LaunchAgentロード失敗調査と修正
#
# 4 件の LaunchAgent（monitor / docker / uptime / refresh）の load 状態を
# `launchctl print gui/<uid>/<label>` ベースで診断する。再発時のトリアージや、
# install.sh 完了後の整合性確認に使う。
#
# 出力:
#   - 構造化ログ: 各 label について 1 行
#       label=<label> status=<loaded|not-loaded> excerpt=<print 出力の冒頭抜粋>
#   - サマリ: 末尾に "N/M loaded" 形式の集計行
#
# 終了コード: 全件 loaded で 0、1 件でも not-loaded があれば 1。
#
# テスト用差し替え:
#   LAUNCHCTL_BIN=/path/to/fake_launchctl   # 実 launchctl を差し替え（mock）
#   DOCTOR_UID=12345                        # gui ドメインの UID を上書き
#   DOCTOR_LABELS="a b c"                   # 検査対象 label 列を上書き（空白区切り）

set -u

BUNDLE_PREFIX="${BUNDLE_PREFIX:-com.github.adachi-tatsuru.machealth}"
DEFAULT_JOBS=(monitor docker uptime refresh)

# 検査対象 label 列の決定
if [ -n "${DOCTOR_LABELS:-}" ]; then
  # 環境変数で完全な label 列を指定（テスト用）
  # shellcheck disable=SC2206
  LABELS=( $DOCTOR_LABELS )
else
  LABELS=()
  for job in "${DEFAULT_JOBS[@]}"; do
    LABELS+=("${BUNDLE_PREFIX}.${job}")
  done
fi

UID_NUM="${DOCTOR_UID:-$(id -u)}"
LAUNCHCTL="${LAUNCHCTL_BIN:-launchctl}"

# 出力テキストを最大 200 文字に切り詰め、改行を半角スペース化（構造化ログを 1 行に保つ）
__doctor_excerpt() {
  local s
  s=$(tr '\n\r' '  ' <"$1" 2>/dev/null || true)
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  if [ ${#s} -gt 200 ]; then
    printf '%s' "${s:0:200}"
  else
    printf '%s' "$s"
  fi
}

PASS=0
FAIL=0
TOTAL=${#LABELS[@]}
FAILED_LABELS=()

for label in "${LABELS[@]}"; do
  tmpfile=$(mktemp)
  rc=0
  "$LAUNCHCTL" print "gui/$UID_NUM/$label" >"$tmpfile" 2>&1 || rc=$?
  excerpt=$(__doctor_excerpt "$tmpfile")
  # not-loaded 判定: "Could not find service" を含む or rc!=0 かつ出力空
  status="loaded"
  if grep -q "Could not find service" "$tmpfile" 2>/dev/null; then
    status="not-loaded"
  elif [ "$rc" -ne 0 ] && [ ! -s "$tmpfile" ]; then
    status="not-loaded"
  fi
  rm -f "$tmpfile"
  printf 'label=%s status=%s excerpt=%s\n' "$label" "$status" "$excerpt"
  if [ "$status" = "loaded" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    # 末尾セグメントだけ取り出す（"…machealth.docker" → "docker"）
    FAILED_LABELS+=("${label##*.}")
  fi
done

if [ "$FAIL" -eq 0 ]; then
  printf '%d/%d loaded\n' "$PASS" "$TOTAL"
  exit 0
fi
ng_joined=""
for nl in "${FAILED_LABELS[@]}"; do
  if [ -z "$ng_joined" ]; then ng_joined="$nl"; else ng_joined="$ng_joined, $nl"; fi
done
printf '%d/%d loaded (NG: %s)\n' "$PASS" "$TOTAL" "$ng_joined"
printf '%d/%d NOT loaded\n' "$FAIL" "$TOTAL"
exit 1
