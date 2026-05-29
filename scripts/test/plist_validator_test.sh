#!/bin/bash
# Mac Health Keeper - plist_validator.sh の単体テスト
#
# issue: 20260529_122242_LaunchAgentロード失敗調査と修正
#
# `scripts/lib/plist_validator.sh` の validate_plist 関数を BDD テストする。
# 4 件の本物の launchagents/*.plist.template に対する OK 経路と、
# 異常系（存在しないファイル / 構文 NG / 必須キー欠落）の戻り値・メッセージを検証する。
#
# BDD 形式（ユースケース → シナリオ → Given/When/Then）は .agents/TEST_BDD_FORMAT.md に従う。
# `make test-shell` から呼ばれ、失敗が 1 件でもあれば非 0 終了する。
# 破壊的副作用なし（一時 dir に検査対象を作成して完結）。
#
# ユースケース:
# validate_plist は plist の plutil -lint 構文検証と LaunchAgent 必須キー（Label /
# ProgramArguments）の存在検査を行い、戻り値 0/1/2 と stdout の固定書式メッセージで結果を返す。

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO_DIR/scripts/lib/plist_validator.sh"
TEMPLATES_DIR="$REPO_DIR/launchagents"

PASS=0
FAIL=0

assert_status() {
  local expected="$1" actual="$2" msg="$3"
  if [ "$actual" -eq "$expected" ]; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (expected status $expected, got $actual)"
  fi
}

assert_grep_text() {
  local pattern="$1" text="$2" msg="$3"
  if printf '%s' "$text" | grep -qE "$pattern"; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (no match for /$pattern/)"
  fi
}

if [ ! -f "$LIB" ]; then
  echo "FAIL: plist_validator.sh not found: $LIB" >&2
  exit 1
fi

# shellcheck source=../lib/plist_validator.sh
source "$LIB"

TMP_DIR=$(mktemp -d -t mac-health-plist-validator.XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT

# ===== UC1: 既存 4 plist テンプレが全件 OK（回帰検知の本命） =====
# ユースケース: launchagents/*.plist.template 4 件は LaunchAgent として最低限のキーを持つ。
for job in monitor docker uptime refresh; do
  tpl="$TEMPLATES_DIR/com.github.adachi-tatsuru.machealth.$job.plist.template"
  # シナリオ: 4 件の plist テンプレ（$job）は validate_plist で 0 を返し OK ラベルを出す。
  # Given: 本物の plist テンプレートファイル
  # When: validate_plist を呼ぶ
  out=$(validate_plist "$tpl")
  rc=$?
  # Then: 戻り値 0
  assert_status 0 "$rc" "UC1-${job}: validate_plist が 0 を返す (${job})"
  # And (Then): stdout が "OK:" で始まる固定書式
  assert_grep_text "^OK: " "$out" "UC1-${job}: OK ラベルを出力する"
done

# ===== UC2: 存在しないファイルは戻り値 1 + "NG: plist not found" =====
# シナリオ: 存在しないパスを渡すと plist not found エラーで戻り値 1。
# Given: 存在しない plist パス
missing="$TMP_DIR/does_not_exist.plist"
# When: validate_plist を呼ぶ
out=$(validate_plist "$missing")
rc=$?
# Then: 戻り値 1
assert_status 1 "$rc" "UC2-S1: 存在しないファイルで戻り値 1"
# And (Then): stdout に "NG: plist not found" を含む
assert_grep_text "^NG: plist not found" "$out" "UC2-S1: plist not found メッセージ"

# ===== UC3: 構文 NG plist は戻り値 1 + "plutil -lint failed" =====
# シナリオ: XML 構文不正な plist は plutil -lint failed で戻り値 1。
# Given: XML 不正な plist
broken="$TMP_DIR/broken.plist"
echo "<<not xml at all>>" >"$broken"
# When: validate_plist を呼ぶ
out=$(validate_plist "$broken")
rc=$?
# Then: 戻り値 1
assert_status 1 "$rc" "UC3-S1: 構文 NG で戻り値 1"
# And (Then): stdout に plutil -lint failed メッセージ
assert_grep_text "plutil -lint failed" "$out" "UC3-S1: plutil -lint failed メッセージ"

# ===== UC4: 必須キー Label 欠落は戻り値 2 + "missing required key Label" =====
# シナリオ: 構文 OK でも Label キーが無い plist は戻り値 2。
# Given: 構文 OK だが Label が無い plist
no_label="$TMP_DIR/no_label.plist"
cat >"$no_label" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/echo</string>
    </array>
</dict>
</plist>
EOF
# When: validate_plist を呼ぶ
out=$(validate_plist "$no_label")
rc=$?
# Then: 戻り値 2
assert_status 2 "$rc" "UC4-S1: Label 欠落で戻り値 2"
# And (Then): missing Label メッセージ
assert_grep_text "missing required key Label" "$out" "UC4-S1: Label 欠落メッセージ"

# ===== UC5: 必須キー ProgramArguments 欠落は戻り値 2 =====
# シナリオ: Label があっても ProgramArguments が無い plist は戻り値 2。
# Given: 構文 OK・Label あり・ProgramArguments 無し
no_prog="$TMP_DIR/no_prog.plist"
cat >"$no_prog" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.example.only.label</string>
</dict>
</plist>
EOF
# When: validate_plist を呼ぶ
out=$(validate_plist "$no_prog")
rc=$?
# Then: 戻り値 2
assert_status 2 "$rc" "UC5-S1: ProgramArguments 欠落で戻り値 2"
# And (Then): missing ProgramArguments メッセージ
assert_grep_text "missing required key ProgramArguments" "$out" "UC5-S1: ProgramArguments 欠落メッセージ"

# --- 集計 ---
echo ""
echo "plist_validator_test: $PASS passed, $FAIL failed"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
exit 0
