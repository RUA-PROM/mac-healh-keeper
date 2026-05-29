#!/bin/bash
# Mac Health Keeper - .github/workflows YAML 構造テスト（release-app.yml + create-release.yaml）
#
# issue: 20260529_123114_CIバージョンstamp_B案実装（3D667BE0-934D-4FC6-B7D0-C423CF45B03F）
#
# 目的:
#   `.github/workflows/release-app.yml` と `.github/workflows/create-release.yaml`
#   の主要な仕様キーが期待どおり配置されていることを軽量にテストする。
#   YAML パーサ（python3 yaml）が利用可能なら構文 lint も行う。
#
# 仕様カバー:
#   - release-app.yml が macos-latest で動作する
#   - fetch-depth: 0 + fetch-tags: true（shallow clone 防止）
#   - softprops/action-gh-release@v2 で files: build/MacHealth-*.zip を添付
#   - release_artifact_validator.sh を呼ぶ step が存在
#   - create-release.yaml は ubuntu-latest のまま壊さず、release-app.yml を
#     workflow_dispatch で起動する step が追加されている
#
# BDD: ユースケース → シナリオ → Given/When/Then は .agents/TEST_BDD_FORMAT.md 準拠。
# 01_要件定義.md UC1-S1 / UC4-S1 に対応。
#
# ユースケース全体:
# 既存 create-release.yaml（ubuntu-latest）と新規 release-app.yml（macos-latest）の
# 役割分離が yaml ファイルレベルで担保されていること。

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
RELEASE_APP_YML="$REPO_DIR/.github/workflows/release-app.yml"
CREATE_RELEASE_YML="$REPO_DIR/.github/workflows/create-release.yaml"
CHECK_YML="$REPO_DIR/.github/workflows/check.yml"

PASS=0
FAIL=0

assert_file_exists() {
  local path="$1" msg="$2"
  if [ -f "$path" ]; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (file not found: $path)"
  fi
}

assert_grep_file() {
  local pattern="$1" file="$2" msg="$3"
  if [ -f "$file" ] && grep -qE -- "$pattern" "$file"; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (no match for /$pattern/ in $file)"
  fi
}

assert_not_grep_file() {
  local pattern="$1" file="$2" msg="$3"
  if [ -f "$file" ] && grep -qE -- "$pattern" "$file"; then
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (unexpected match for /$pattern/ in $file)"
  else
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  fi
}

# ===== UC1: release-app.yml の存在と必須キー =====
# ユースケース:
# 新規 workflow `release-app.yml` が必要なキー（macos-latest, fetch-depth: 0,
# fetch-tags: true, softprops/action-gh-release, validator 呼び出し）を備え、
# B 案の責務を全て表現していること（01 UC1-S1）。

# シナリオ: ファイルが存在する。
# Given: リポジトリ
# When: .github/workflows/release-app.yml の存在を確認する
# Then: ファイルが存在する
assert_file_exists "$RELEASE_APP_YML" "UC1-S1: release-app.yml が存在する"

# シナリオ: runs-on: macos-latest が宣言されている（B 案の前提）。
# Given: release-app.yml
# When: 'runs-on: macos-latest' を grep する
# Then: ヒットする
assert_grep_file "runs-on: macos-latest" "$RELEASE_APP_YML" "UC1-S2: runs-on: macos-latest が宣言されている"

# シナリオ: actions/checkout@v4 が fetch-depth: 0 + fetch-tags: true 付き。
# Given: release-app.yml
# When: 各キーを grep する
# Then: 3 件全てヒットする
assert_grep_file "actions/checkout@v4" "$RELEASE_APP_YML" "UC1-S3: actions/checkout@v4 を使用"
assert_grep_file "fetch-depth: 0" "$RELEASE_APP_YML" "UC1-S3: fetch-depth: 0 を指定"
assert_grep_file "fetch-tags: true" "$RELEASE_APP_YML" "UC1-S3: fetch-tags: true を指定"

# シナリオ: make build / make package / make check の 3 ステップを呼ぶ。
# Given: release-app.yml
# When: 各 make ターゲットを grep する
# Then: 全てヒット
assert_grep_file "make build" "$RELEASE_APP_YML" "UC1-S4: make build ステップが存在"
assert_grep_file "make package" "$RELEASE_APP_YML" "UC1-S4: make package ステップが存在"
assert_grep_file "make check" "$RELEASE_APP_YML" "UC1-S4: make check ステップが存在（回帰防止）"

# シナリオ: release_artifact_validator.sh を呼ぶ step がある。
# Given: release-app.yml
# When: scripts/lib/release_artifact_validator.sh を grep する
# Then: ヒットする
assert_grep_file "scripts/lib/release_artifact_validator.sh" "$RELEASE_APP_YML" \
  "UC1-S5: release_artifact_validator.sh 呼び出しが存在"

# シナリオ: gh release create で build/MacHealth-*.zip を Release 作成と同時に添付する。
# Given: release-app.yml
# When: 'gh release create' と zip path 参照を grep する
# Then: 両方ヒットする
# 設計判断: Immutable Releases (リポジトリ設定) では Release 作成時に asset を含めないと
# 後から添付できない (HTTP 422)。release-app.yml が Release 作成と asset 添付を
# atomic に行う契約に変更（softprops/action-gh-release も gh release upload も使わない）。
assert_grep_file "gh release create" "$RELEASE_APP_YML" \
  "UC1-S6: gh release create で Release 作成 + artifact 添付を atomic に実行"
assert_grep_file "ZIP_PATH" "$RELEASE_APP_YML" \
  "UC1-S6: ZIP_PATH 環境変数で zip パスを引き渡し"
# softprops/action-gh-release は使わない契約
assert_not_grep_file "softprops/action-gh-release" "$RELEASE_APP_YML" \
  "UC1-S6: softprops/action-gh-release は使わない（immutable release 対策）"
# --target を渡して target_commitish の不整合（refs/heads/main へのデフォルト fallback）を防ぐ
assert_grep_file "\-\-target" "$RELEASE_APP_YML" \
  "UC1-S6: gh release create に --target を指定（tag commit に固定）"

# シナリオ: permissions: contents: write を最小権限で明示している。
# Given: release-app.yml
# When: permissions ブロックを grep する
# Then: ヒットする
assert_grep_file "permissions:" "$RELEASE_APP_YML" "UC1-S7: permissions ブロックを明示"
assert_grep_file "contents: write" "$RELEASE_APP_YML" "UC1-S7: contents: write 権限を付与"

# シナリオ: trigger は push: tags ['v*'] + workflow_dispatch（tag 入力）。
# Given: release-app.yml
# When: on: trigger 設定を grep する
# Then: 両方ヒット
assert_grep_file "tags:" "$RELEASE_APP_YML" "UC1-S8: push: tags trigger を宣言"
assert_grep_file 'v\*' "$RELEASE_APP_YML" "UC1-S8: v* tag pattern を宣言"
assert_grep_file "workflow_dispatch:" "$RELEASE_APP_YML" "UC1-S8: workflow_dispatch 手動 trigger を宣言"

# ===== UC2: 既存 create-release.yaml の振る舞いが壊れていない =====
# ユースケース:
# 既存 `create-release.yaml` は ubuntu-latest で tag/Release 生成だけを担い、
# 本 issue では release-app.yml を起動する step を 1 つだけ追加（最小修正）。

# シナリオ: create-release.yaml は依然 ubuntu-latest のまま。
# Given: create-release.yaml
# When: runs-on を grep する
# Then: ubuntu-latest が残っている / macos-latest になっていない
assert_grep_file "runs-on: ubuntu-latest" "$CREATE_RELEASE_YML" \
  "UC2-S1: create-release.yaml は ubuntu-latest のまま（壊していない）"
assert_not_grep_file "runs-on: macos-latest" "$CREATE_RELEASE_YML" \
  "UC2-S1: create-release.yaml に macos-latest 化は混入していない"

# シナリオ: 既存の tag 命名 vYYYYMMDD.HHMMSS は維持されている。
# Given: create-release.yaml
# When: TZ=Asia/Tokyo date pattern を grep する
# Then: ヒットする（タグ命名規約は変更しない契約）
assert_grep_file "TZ=Asia/Tokyo date" "$CREATE_RELEASE_YML" \
  "UC2-S2: 既存 tag 命名（vYYYYMMDD.HHMMSS）が維持されている"
# Release 作成は release-app.yml に移譲したため、create-release.yaml は gh release create を呼ばない（immutable release 対策）。
assert_not_grep_file "gh release create" "$CREATE_RELEASE_YML" \
  "UC2-S2: create-release.yaml は gh release create を呼ばない（release-app.yml に移譲）"
assert_grep_file "git tag" "$CREATE_RELEASE_YML" \
  "UC2-S2: create-release.yaml は git tag 作成のみ担当"
assert_grep_file "git push origin" "$CREATE_RELEASE_YML" \
  "UC2-S2: create-release.yaml は tag push を担当"

# シナリオ: release-app.yml を workflow_dispatch で起動する step が追加されている。
# Given: create-release.yaml
# When: gh workflow run release-app.yml を grep する
# Then: ヒットする
assert_grep_file "gh workflow run release-app.yml" "$CREATE_RELEASE_YML" \
  "UC2-S3: create-release.yaml が release-app.yml を dispatch する step を持つ"
assert_grep_file "field tag=" "$CREATE_RELEASE_YML" \
  "UC2-S3: dispatch は tag 入力を field で渡す"

# シナリオ: gh workflow run を呼ぶため actions: write permission を最小権限で付与する。
# Given: create-release.yaml
# When: permissions ブロックを確認する
# Then: actions: write が含まれる
assert_grep_file "actions: write" "$CREATE_RELEASE_YML" \
  "UC2-S4: create-release.yaml に actions: write 権限が付与されている（workflow_dispatch 用）"

# ===== UC3: check.yml は本 issue で触っていない（回帰なし） =====
# ユースケース:
# check.yml（既存 PR/push CI）は本 issue の対象外。意図しない変更が混入しないことを
# テストレベルで監視する。

# シナリオ: check.yml は依然 macos-latest で make check を実行している。
# Given: check.yml
# When: 主要キーを grep する
# Then: 維持されている
assert_grep_file "runs-on: macos-latest" "$CHECK_YML" "UC3-S1: check.yml の runs-on: macos-latest 維持"
assert_grep_file "make check" "$CHECK_YML" "UC3-S1: check.yml の make check 維持"

# ===== UC4: YAML パーサ（python3 + PyYAML）が利用可能なら構文 lint =====
# ユースケース:
# yaml の構文エラーをコミット前に検知する。yamllint や python3 yaml が無い環境では
# SKIP し、利用可能環境（CI macos-latest や開発機）では構文を検証する。

# シナリオ: python3 -c "import yaml" が動く環境では release-app.yml をパースする。
# Given: release-app.yml が存在
# When: python3 で yaml をパースする（失敗時は SKIP）
# Then: 成功 = 構文 OK
if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' 2>/dev/null; then
  if python3 -c "import yaml,sys; yaml.safe_load(open('$RELEASE_APP_YML'))" 2>/dev/null; then
    PASS=$((PASS + 1)); echo "  ok   - UC4-S1: release-app.yml が python yaml parser でパース可能"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - UC4-S1: release-app.yml の yaml 構文エラー"
  fi
  if python3 -c "import yaml,sys; yaml.safe_load(open('$CREATE_RELEASE_YML'))" 2>/dev/null; then
    PASS=$((PASS + 1)); echo "  ok   - UC4-S2: create-release.yaml が python yaml parser でパース可能"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - UC4-S2: create-release.yaml の yaml 構文エラー"
  fi
  if python3 -c "import yaml,sys; yaml.safe_load(open('$CHECK_YML'))" 2>/dev/null; then
    PASS=$((PASS + 1)); echo "  ok   - UC4-S3: check.yml が python yaml parser でパース可能"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - UC4-S3: check.yml の yaml 構文エラー"
  fi
else
  PASS=$((PASS + 1)); echo "  ok   - UC4: SKIP（python3 + PyYAML が利用不可な環境）"
fi

# --- 集計 ---
echo ""
echo "workflow_release_app_test: $PASS passed, $FAIL failed"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
exit 0
