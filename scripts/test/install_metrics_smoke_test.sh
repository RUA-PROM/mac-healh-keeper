#!/bin/bash
# Mac Health Keeper - install / metrics.sh 配置の smoke test
#
# issue: 20260529_083530_メトリクス非表示修正 フォロー
#
# 目的:
#   今回の不具合の根本原因（リポジトリ側に metrics.sh が無い or install.sh の cp 範囲から
#   抜けている）を回帰検知する。アプリだけが新しく metrics.sh は古い、という運用ミスは
#   別途の Swift 側エラーバナーで検知できるが、リポジトリ側の構造的欠落はここで止める。
#
# 検証:
#   UC1-S1: リポジトリの scripts/lib/metrics.sh が物理的に存在する。
#   UC1-S2: install.sh が scripts/lib/ を $HOME/.local/bin/mac-health/lib/ にコピーする
#          一行（`cp -R "$REPO_DIR/scripts/lib/." "$INSTALL_DIR/lib/"`）を含む。
#   UC2-S1: scripts/lib/metrics.sh を source して metrics_* 純粋関数が呼べる
#          （つまり「metrics.sh は配置すれば動く」契約を満たす）。
#   UC3-S1: HEREDOC で組んだ一時 HOME 上に scripts/lib をコピーするだけで、
#          `bash <copy>/metrics.sh load`（CLI 経路）が空文字以外を返す。
#
# 失敗が 1 件でもあれば非 0 終了する。`make test-shell` から呼ばれる。

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PASS=0
FAIL=0

assert_eq() {
  local expected="$1" actual="$2" msg="$3"
  if [ "$actual" = "$expected" ]; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (expected '$expected', got '$actual')"
  fi
}

assert_nonempty() {
  local actual="$1" msg="$2"
  if [ -n "$actual" ]; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (got empty string)"
  fi
}

assert_file_exists() {
  local path="$1" msg="$2"
  if [ -f "$path" ]; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (file not found: $path)"
  fi
}

assert_grep() {
  local pattern="$1" file="$2" msg="$3"
  if grep -q -- "$pattern" "$file"; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (pattern not found in $file: $pattern)"
  fi
}

# ===== ユースケース 1: リポジトリ構造の健全性 =====
# UC1: 再リファクタや install.sh の変更で metrics.sh が抜け落ちないことを保証する。

# シナリオ: scripts/lib/metrics.sh がリポジトリに物理的に存在する。
# Given: REPO_DIR 配下の想定パス
metrics_path="$REPO_DIR/scripts/lib/metrics.sh"
# When: ファイル存在を検査する
# Then: 存在する（== 配布物の元ファイルが消えていない）
assert_file_exists "$metrics_path" "UC1-S1: scripts/lib/metrics.sh が物理的に存在する"

# シナリオ: install.sh が scripts/lib/ を $INSTALL_DIR/lib/ にコピーする行を含む。
# Given: install.sh
install_sh="$REPO_DIR/install.sh"
assert_file_exists "$install_sh" "UC1-S2 前提: install.sh が存在する"
# When: 当該 cp 行の存在を grep で確認する
# Then: `cp -R "$REPO_DIR/scripts/lib/." "$INSTALL_DIR/lib/"` 相当が含まれる
assert_grep 'scripts/lib/\." *"\$INSTALL_DIR/lib/"' "$install_sh" \
  "UC1-S2: install.sh が scripts/lib/ を INSTALL_DIR/lib/ にコピーする"

# ===== ユースケース 2: metrics.sh の source 契約 =====
# UC2: metrics.sh 自体が引き続き「source 可能・純粋関数群を露出する」契約を満たすことを保証する。

# シナリオ: scripts/lib/metrics.sh を source し、純粋パース関数 metrics_parse_load_1m が呼べる。
# Given: source 用シェル
# When: source して既知関数 metrics_parse_load_1m を固定テキストで呼ぶ
out=$(
  # shellcheck disable=SC1090
  source "$metrics_path" 2>/dev/null
  metrics_parse_load_1m "12:00  up 1 day, load averages: 1.23 2.34 3.45"
)
# Then: "1.2"（%.1f 整形）が返る
assert_eq "1.2" "$out" "UC2-S1: source 後に metrics_parse_load_1m が固定入力で 1.2 を返す"

# ===== ユースケース 3: CLI 経路（bash metrics.sh <metric>）の smoke =====
# UC3: 「アプリが /bin/bash <path> <metric> を起動して値を取得する」配布物経路を、
#       一時 HOME ディレクトリで擬似的に再現して、値が返ることを smoke 検証する。
#       実 OS の sysctl/vm_stat 等に依存するので「空文字でないこと」のみ判定する。

# シナリオ: 一時 HOME へ scripts/lib をコピーし、bash metrics.sh load が空文字以外を返す。
# Given: 一時 HOME を作って scripts/lib/ をコピーする
tmpdir=$(mktemp -d -t mac-health-smoke.XXXXXX)
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir/.local/bin/mac-health/lib"
cp -R "$REPO_DIR/scripts/lib/." "$tmpdir/.local/bin/mac-health/lib/"
target="$tmpdir/.local/bin/mac-health/lib/metrics.sh"
assert_file_exists "$target" "UC3-S1 前提: コピー後の lib/metrics.sh が存在する"

# When: bash metrics.sh load を実コマンド経由で呼ぶ
load_out=$(bash "$target" load 2>/dev/null || true)
# Then: 空文字以外（実 OS の uptime が返れば必ず値が入る）
assert_nonempty "$load_out" "UC3-S1: bash metrics.sh load が空文字以外の値を返す"

# And (When): swap も呼ぶ
swap_out=$(bash "$target" swap 2>/dev/null || true)
# And (Then): swap も空文字以外
assert_nonempty "$swap_out" "UC3-S1: bash metrics.sh swap が空文字以外の値を返す"

# And (When): free も呼ぶ
free_out=$(bash "$target" free 2>/dev/null || true)
# And (Then): free も空文字以外
assert_nonempty "$free_out" "UC3-S1: bash metrics.sh free が空文字以外の値を返す"

# --- 集計 ---
echo ""
echo "install_metrics_smoke_test: $PASS passed, $FAIL failed"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
exit 0
