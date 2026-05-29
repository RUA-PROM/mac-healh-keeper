#!/bin/bash
# Mac Health Keeper - CI Release smoke test
#
# issue: 20260529_123114_CIバージョンstamp_B案実装（3D667BE0-934D-4FC6-B7D0-C423CF45B03F）
#
# 目的:
#   `.github/workflows/release-app.yml` が実行する一連の flow（make build → make package
#   → release_artifact_validator.sh）が、ローカルで擬似実行できることを保証する。
#   実 CI に出す前に「壊れていないか」をローカルで再現することが本テストの責務。
#
# 仕様:
#   - 本テストは破壊的（リポジトリの build/ ディレクトリを実際に作る）。
#     `make clean` を冒頭と末尾で呼び副作用を最小化する。
#   - ローカル macOS でのみ意味があるため、Linux などで実行された場合は SKIP する
#     （Makefile build は plutil / PlistBuddy を要求するため）。
#   - 全 UC を順次実行し、いずれか失敗すれば非 0 終了する。
#
# BDD: ユースケース → シナリオ → Given/When/Then は .agents/TEST_BDD_FORMAT.md 準拠。
# 01_要件定義.md UC1-S1 / UC2-S1 / UC4-S1 に対応。
#
# ユースケース全体:
# CI Release ワークフローの主要ステップ（build → package → validator）を、
# ローカルで丸ごと擬似実行し、artifact が正しく生成されることを保証する。

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
VALIDATOR="$REPO_DIR/scripts/lib/release_artifact_validator.sh"

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

assert_file_exists() {
  local path="$1" msg="$2"
  if [ -f "$path" ]; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (file not found: $path)"
  fi
}

assert_dir_exists() {
  local path="$1" msg="$2"
  if [ -d "$path" ]; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (dir not found: $path)"
  fi
}

# macOS 以外は SKIP（CI smoke は macos-latest 専用）
if [ "$(uname -s)" != "Darwin" ]; then
  echo "ci_release_smoke_test: SKIP (Darwin/macOS only; current uname=$(uname -s))"
  exit 0
fi

# swiftc が無い環境（CommandLineTools の特定構成）は SKIP
if ! command -v swiftc >/dev/null 2>&1; then
  echo "ci_release_smoke_test: SKIP (swiftc not found)"
  exit 0
fi

# 前提
if [ ! -x "$VALIDATOR" ] && [ ! -f "$VALIDATOR" ]; then
  echo "FAIL: release_artifact_validator.sh not found: $VALIDATOR" >&2
  exit 1
fi

# ===== UC1: make build → make package → validator が一気通貫で成功する =====
# ユースケース:
# CI release-app.yml が踏む build → package → validate の流れが、
# ローカル macOS でも同じ exit 0 で完走できること（01 UC1-S1 / UC2-S1）。

# シナリオ: clean 状態から make build → make package → release_artifact_validator が exit 0 で成功する。
# Given: 直前の build/ をクリーンにする
cd "$REPO_DIR"
echo "==> make clean (前準備)"
make clean >/dev/null 2>&1 || true

# When: make build を実行する
echo "==> make build"
set +e
make build >/tmp/ci_smoke_build.log 2>&1
rc_build=$?
set -e
# Then: 終了コード 0
assert_status 0 "$rc_build" "UC1-S1: make build が終了コード 0"
# And (Then): build/MacHealth.app が組み立てられている
assert_dir_exists "$REPO_DIR/build/MacHealth.app" "UC1-S1: build/MacHealth.app ディレクトリ存在"
assert_file_exists "$REPO_DIR/build/MacHealth.app/Contents/MacOS/MacHealth" "UC1-S1: バイナリ存在"
assert_file_exists "$REPO_DIR/build/MacHealth.app/Contents/Info.plist" "UC1-S1: Info.plist 存在"

# And (When): make package を実行する
echo "==> make package"
set +e
make package >/tmp/ci_smoke_package.log 2>&1
rc_package=$?
set -e
# And (Then): 終了コード 0
assert_status 0 "$rc_package" "UC1-S1: make package が終了コード 0"

# And (When): build/MacHealth-*.zip を取得して validator にかける
zip_path=$(ls "$REPO_DIR"/build/MacHealth-*.zip 2>/dev/null | head -n1)
# And (Then): zip ファイルが生成されている
if [ -n "$zip_path" ] && [ -f "$zip_path" ]; then
  PASS=$((PASS + 1)); echo "  ok   - UC1-S1: zip 生成済み ($zip_path)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL - UC1-S1: zip が見つからない (build/MacHealth-*.zip)"
fi

if [ -n "$zip_path" ] && [ -f "$zip_path" ]; then
  # And (When): release_artifact_validator.sh を実行する（期待値は git describe 経由）
  set +e
  validator_out=$(bash "$VALIDATOR" "$zip_path" "" "$REPO_DIR" 2>&1)
  rc_validator=$?
  set -e
  # And (Then): 終了コード 0
  assert_status 0 "$rc_validator" "UC1-S1: validator が終了コード 0"
  # And (Then): OK サマリ
  if printf '%s' "$validator_out" | grep -q "release_artifact_validator: OK"; then
    PASS=$((PASS + 1)); echo "  ok   - UC1-S1: validator OK サマリ"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - UC1-S1: validator OK サマリが出ていない"
    echo "    --- validator output ---"
    printf '%s\n' "$validator_out" | sed 's/^/    /'
  fi
fi

# ===== UC2: make clean-app で .app だけ削除しバイナリは温存される（CI 上の段階的 build に必要） =====
# ユースケース:
# CI / ローカルで `make build` → 検査 → 再ビルド時に .app だけ削除して
# build-bin の swiftc コスト（数十秒）を節約する経路が壊れていないこと。

# シナリオ: make clean-app 後、build/MacHealth.app は消えるが build/MacHealth は残る。
# Given: 直前の UC1 で build/MacHealth.app と build/MacHealth が両方存在する状態
# When: make clean-app を実行する
echo "==> make clean-app"
make clean-app >/dev/null 2>&1
# Then: build/MacHealth.app が削除されている
if [ ! -d "$REPO_DIR/build/MacHealth.app" ]; then
  PASS=$((PASS + 1)); echo "  ok   - UC2-S1: build/MacHealth.app が削除された"
else
  FAIL=$((FAIL + 1)); echo "  FAIL - UC2-S1: build/MacHealth.app がまだ存在する"
fi
# And (Then): build/MacHealth バイナリは温存されている
if [ -f "$REPO_DIR/build/MacHealth" ]; then
  PASS=$((PASS + 1)); echo "  ok   - UC2-S1: build/MacHealth バイナリは温存"
else
  FAIL=$((FAIL + 1)); echo "  FAIL - UC2-S1: build/MacHealth バイナリが温存されていない"
fi

# ===== UC3: make clean で build/ が空になる =====
# ユースケース:
# CI 上で artifact upload 後に build/ を完全クリーンに戻せること。

# シナリオ: make clean 後、build/ ディレクトリ自体が無くなる。
# Given: build/ が存在する状態
# When: make clean を実行する
echo "==> make clean"
make clean >/dev/null 2>&1
# Then: build/ が存在しない
if [ ! -d "$REPO_DIR/build" ]; then
  PASS=$((PASS + 1)); echo "  ok   - UC3-S1: build/ ディレクトリが削除された"
else
  FAIL=$((FAIL + 1)); echo "  FAIL - UC3-S1: build/ ディレクトリがまだ存在する"
fi

# ===== UC4: shallow clone 警告経路（git describe fallback の検知）=====
# ユースケース:
# CI の checkout で fetch-depth: 0 が漏れた場合、make build の version_stamp が
# 0.0.0-DEV に fallback する。validator は期待値（git describe）を渡されると
# mismatch として落ちる契約。これにより CI 側で fetch-depth 漏れを即検知できる。

# シナリオ: わざと 0.0.0-DEV stamp された artifact を本リポジトリの git describe 期待値で
# validator にかけると mismatch で NG。
# Given: 0.0.0-DEV stamp の擬似 artifact
tmp_fixtures=$(mktemp -d -t ci-smoke-fixture.XXXXXX)
# shellcheck disable=SC2064
trap "rm -rf '$tmp_fixtures'" EXIT
fake_app="$tmp_fixtures/MacHealth.app"
mkdir -p "$fake_app/Contents/MacOS" "$fake_app/Contents/Resources"
cat > "$fake_app/Contents/MacOS/MacHealth" <<'EOS'
#!/bin/bash
echo dummy
EOS
chmod +x "$fake_app/Contents/MacOS/MacHealth"
cp "$REPO_DIR/src/Info.plist" "$fake_app/Contents/Info.plist"
# CFBundleVersion はそのまま 0.0.0-DEV テンプレ値を維持
(cd "$tmp_fixtures" && zip -r -q "fake.zip" MacHealth.app)

# When: 本リポジトリの git describe 期待値を渡して validator を実行する
expected_real=$(git -C "$REPO_DIR" describe --tags --always 2>/dev/null || echo "FALLBACK")
set +e
out_uc4=$(bash "$VALIDATOR" "$tmp_fixtures/fake.zip" "$expected_real" 2>&1)
rc_uc4=$?
set -e

# Then: 期待値と異なる（0.0.0-DEV != tag）ので NG = 終了コード 1
# ただし、git describe 自体が "FALLBACK" になっている環境では一致してしまうため判定を分岐
if [ "$expected_real" != "0.0.0-DEV" ]; then
  assert_status 1 "$rc_uc4" "UC4-S1: 0.0.0-DEV + 期待値（tag）で validator が NG"
  # And (Then): mismatch メッセージ
  if printf '%s' "$out_uc4" | grep -q "CFBundleVersion mismatch"; then
    PASS=$((PASS + 1)); echo "  ok   - UC4-S1: mismatch メッセージで shallow clone 検知"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - UC4-S1: mismatch メッセージが出ていない"
  fi
else
  # 本テスト環境が shallow clone 等で git describe が fallback している場合は SKIP 扱い
  PASS=$((PASS + 1)); echo "  ok   - UC4-S1: SKIP（実環境の git describe が既に fallback）"
fi

# --- 集計 ---
echo ""
echo "ci_release_smoke_test: $PASS passed, $FAIL failed"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
exit 0
