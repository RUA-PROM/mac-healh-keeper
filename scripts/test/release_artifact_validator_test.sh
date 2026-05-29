#!/bin/bash
# Mac Health Keeper - release_artifact_validator.sh の単体テスト
#
# issue: 20260529_123114_CIバージョンstamp_B案実装（3D667BE0-934D-4FC6-B7D0-C423CF45B03F）
#
# `scripts/lib/release_artifact_validator.sh` を一時 fixture（.app + zip）を作って
# BDD 形式で検証する。
#
# BDD 形式（ユースケース → シナリオ → Given/When/Then）は .agents/TEST_BDD_FORMAT.md に従う。
# 01_要件定義.md UC1-S1, UC2-S1, UC3-S1, UC4-S1 + 03_実装計画.md タスク 1〜5 に対応。
# `make test-shell` から呼ばれ、失敗が 1 件でもあれば非 0 終了する。
# 破壊的副作用なし（mktemp で作成した一時ディレクトリで完結）。
#
# ユースケース全体（このテストファイルが守る不変条件）:
# `scripts/lib/release_artifact_validator.sh` が、CI で生成された `.app` zip に対して
# 必須 Info.plist キーの存在・CFBundleVersion の一致・実行バイナリの存在・
# CFBundleExecutable と MacOS 名の整合性・shallow clone fallback（0.0.0-DEV）の検知を
# 一貫して判定できること。CI とローカルで同じ判定が得られることを保証する。

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO_DIR/scripts/lib/release_artifact_validator.sh"
SRC_PLIST="$REPO_DIR/src/Info.plist"

PASS=0
FAIL=0

# --- 自前 assert ヘルパ（build_app_bundle_test.sh と同流儀） ---

assert_status() {
  local expected="$1" actual="$2" msg="$3"
  if [ "$actual" -eq "$expected" ]; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (expected status $expected, got $actual)"
  fi
}

assert_grep() {
  local pattern="$1" text="$2" msg="$3"
  if printf '%s' "$text" | grep -qE -- "$pattern"; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (no match for /$pattern/)"
  fi
}

assert_no_match() {
  local pattern="$1" text="$2" msg="$3"
  if printf '%s' "$text" | grep -qE -- "$pattern"; then
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (unexpected match for /$pattern/)"
  else
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  fi
}

# 前提
if [ ! -f "$LIB" ]; then
  echo "FAIL: release_artifact_validator.sh not found: $LIB" >&2
  exit 1
fi
if [ ! -f "$SRC_PLIST" ]; then
  echo "FAIL: src/Info.plist not found: $SRC_PLIST" >&2
  exit 1
fi
if [ ! -x /usr/libexec/PlistBuddy ]; then
  echo "FAIL: PlistBuddy not found (macOS 必須)" >&2
  exit 1
fi
if ! command -v zip >/dev/null 2>&1; then
  echo "FAIL: zip command not found" >&2
  exit 1
fi

TMP_ROOT=$(mktemp -d -t mac-health-validator.XXXXXX)
trap 'rm -rf "$TMP_ROOT"' EXIT

# ヘルパ: 正常な .app + zip を生成する
# 引数: <dest-dir> <version-string>
make_app_zip() {
  local dest="$1"
  local ver="$2"
  local app="$dest/MacHealth.app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  # ダミー実行ファイル
  cat > "$app/Contents/MacOS/MacHealth" <<'EOS'
#!/bin/bash
echo "MacHealth dummy"
EOS
  chmod +x "$app/Contents/MacOS/MacHealth"
  # Info.plist を src からコピーして CFBundleVersion を上書き
  cp "$SRC_PLIST" "$app/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $ver" "$app/Contents/Info.plist" >/dev/null
  # zip 化
  (cd "$dest" && zip -r -q "MacHealth-$ver.zip" "MacHealth.app")
  echo "$dest/MacHealth-$ver.zip"
}

# ===== UC1: 正常系 — 必須キーが揃った .app zip を検証して exit 0 =====
# ユースケース:
# 正常に組み立てられた .app を zip 化した artifact に対して、release_artifact_validator が
# 期待値一致 + 全 OK で exit 0 を返すこと（01 UC1-S1, UC2-S1）。

# シナリオ: 期待値 v1.0.0 と一致する CFBundleVersion を持つ artifact が OK 判定される。
# Given: 正常な .app zip（CFBundleVersion=v1.0.0）
fx1="$TMP_ROOT/uc1"; mkdir -p "$fx1"
zip1=$(make_app_zip "$fx1" "v1.0.0")

# When: release_artifact_validator.sh を期待値付きで実行する
set +e
out1=$(bash "$LIB" "$zip1" "v1.0.0" 2>&1)
rc1=$?
set -e

# Then: 終了コード 0
assert_status 0 "$rc1" "UC1-S1: 正常系で終了コード 0"
# And (Then): stdout の末尾に OK サマリ
assert_grep "release_artifact_validator: OK" "$out1" "UC1-S1: OK サマリが出力される"
# And (Then): 6 つの必須キー全てが OK 行で出る
for key in CFBundleExecutable CFBundleIdentifier CFBundleName CFBundlePackageType CFBundleVersion CFBundleShortVersionString; do
  assert_grep "OK.*Info.plist key '$key'" "$out1" "UC1-S1: 必須キー $key が OK"
done
# And (Then): CFBundleVersion 一致 OK 行
assert_grep "OK.*CFBundleVersion matches expected" "$out1" "UC1-S1: CFBundleVersion 一致 OK"

# ===== UC2: CFBundleVersion 不一致 — exit 1 + NG メッセージ =====
# ユースケース:
# 期待値と CFBundleVersion が異なる artifact を NG 判定し exit 1 を返すこと
# （01 UC2-S1 / UC3-S1：A 案 install.sh stamp と B 案 CI artifact の一致観点）。

# シナリオ: artifact の CFBundleVersion=v1.0.0、期待値=v2.0.0 で NG。
# Given: artifact の CFBundleVersion=v1.0.0 を作る
fx2="$TMP_ROOT/uc2"; mkdir -p "$fx2"
zip2=$(make_app_zip "$fx2" "v1.0.0")

# When: 期待値 v2.0.0 を渡して検証する
set +e
out2=$(bash "$LIB" "$zip2" "v2.0.0" 2>&1)
rc2=$?
set -e

# Then: 終了コード 1
assert_status 1 "$rc2" "UC2-S1: 不一致で終了コード 1"
# And (Then): NG メッセージに mismatch が含まれる
assert_grep "NG.*CFBundleVersion mismatch" "$out2" "UC2-S1: mismatch NG メッセージ"
# And (Then): 末尾 NG サマリ
assert_grep "release_artifact_validator: NG" "$out2" "UC2-S1: NG サマリ"

# ===== UC3: 必須キー欠落 — exit 1 + 欠落キー明示 =====
# ユースケース:
# Info.plist から CFBundleIdentifier 等の必須キーが欠落した artifact を
# NG 判定し、stderr に欠落キーを明示する（回帰検知）。

# シナリオ: CFBundleIdentifier を削除した .app zip を検証すると NG。
# Given: 正常 .app から CFBundleIdentifier を削除して zip 化
fx3="$TMP_ROOT/uc3"; mkdir -p "$fx3"
app3="$fx3/MacHealth.app"
mkdir -p "$app3/Contents/MacOS" "$app3/Contents/Resources"
cat > "$app3/Contents/MacOS/MacHealth" <<'EOS'
#!/bin/bash
echo "uc3"
EOS
chmod +x "$app3/Contents/MacOS/MacHealth"
cp "$SRC_PLIST" "$app3/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion v1.0.0" "$app3/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Delete :CFBundleIdentifier" "$app3/Contents/Info.plist" >/dev/null
(cd "$fx3" && zip -r -q MacHealth-v1.0.0.zip MacHealth.app)
zip3="$fx3/MacHealth-v1.0.0.zip"

# When: release_artifact_validator.sh を期待値付きで実行する
set +e
out3=$(bash "$LIB" "$zip3" "v1.0.0" 2>&1)
rc3=$?
set -e

# Then: 終了コード 1
assert_status 1 "$rc3" "UC3-S1: 必須キー欠落で終了コード 1"
# And (Then): 欠落キーが NG 行に明示される（"key 'CFBundleIdentifier' missing"）
assert_grep "NG.*key 'CFBundleIdentifier' missing" "$out3" "UC3-S1: CFBundleIdentifier 欠落 NG"
# And (Then): missing keys: のサマリ行に CFBundleIdentifier が含まれる
assert_grep "missing keys:.*CFBundleIdentifier" "$out3" "UC3-S1: missing keys: サマリ"

# ===== UC4: バイナリ不在 — exit 1 =====
# ユースケース:
# .app/Contents/MacOS/MacHealth が無い壊れた zip を NG 判定する。

# シナリオ: 実行バイナリを削除した .app zip を検証すると NG。
# Given: 正常な .app から MacHealth バイナリだけ削除した zip
fx4="$TMP_ROOT/uc4"; mkdir -p "$fx4"
app4="$fx4/MacHealth.app"
mkdir -p "$app4/Contents/MacOS" "$app4/Contents/Resources"
cp "$SRC_PLIST" "$app4/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion v1.0.0" "$app4/Contents/Info.plist" >/dev/null
# わざと MacHealth バイナリを置かない
(cd "$fx4" && zip -r -q MacHealth-v1.0.0.zip MacHealth.app)
zip4="$fx4/MacHealth-v1.0.0.zip"

# When: release_artifact_validator.sh を実行する
set +e
out4=$(bash "$LIB" "$zip4" "v1.0.0" 2>&1)
rc4=$?
set -e

# Then: 終了コード 1
assert_status 1 "$rc4" "UC4-S1: バイナリ不在で終了コード 1"
# And (Then): NG メッセージに MacHealth missing
assert_grep "NG.*Contents/MacOS/MacHealth missing" "$out4" "UC4-S1: バイナリ不在 NG"

# ===== UC5: zip 自体が壊れている / 存在しない — exit 1 =====
# ユースケース:
# 入力 zip が存在しない、または .zip 以外の拡張子の場合に明確に失敗する。

# シナリオ: 存在しない zip パスを渡すと exit 1 + "zip not found"。
# Given: 存在しない zip パス
missing_zip="$TMP_ROOT/does-not-exist.zip"

# When: release_artifact_validator.sh を実行する
set +e
out5=$(bash "$LIB" "$missing_zip" 2>&1)
rc5=$?
set -e

# Then: 終了コード 1
assert_status 1 "$rc5" "UC5-S1: 存在しない zip で終了コード 1"
# And (Then): stderr に zip not found
assert_grep "zip not found" "$out5" "UC5-S1: zip not found エラー"

# シナリオ: .zip 拡張子でないファイルを渡すと exit 1 + "must be a .zip"。
# Given: .txt 拡張子のファイル
notzip="$TMP_ROOT/not.txt"
echo "not zip" > "$notzip"
# When: release_artifact_validator.sh を実行する
set +e
out5b=$(bash "$LIB" "$notzip" 2>&1)
rc5b=$?
set -e
# Then: 終了コード 1 + must be a .zip
assert_status 1 "$rc5b" "UC5-S2: 非 zip ファイルで終了コード 1"
assert_grep "must be a .zip" "$out5b" "UC5-S2: must be a .zip エラー"

# シナリオ: 引数 0 件は exit 2 + Usage。
# Given: 引数なし
# When: release_artifact_validator.sh を引数なしで実行する
set +e
out5c=$(bash "$LIB" 2>&1)
rc5c=$?
set -e
# Then: 終了コード 2 + Usage
assert_status 2 "$rc5c" "UC5-S3: 引数 0 件で終了コード 2"
assert_grep "Usage:" "$out5c" "UC5-S3: Usage 出力"

# ===== UC6: 0.0.0-DEV fallback — WARN を出して exit 0（期待値未指定時）=====
# ユースケース:
# 期待値を渡さない場合（ローカル検証など）、CFBundleVersion=0.0.0-DEV は
# shallow clone fallback の可能性として WARN を stderr に出すが、
# 構造的に問題なければ exit 0 で許容する（CI 側は期待値を渡して厳格化する）。

# シナリオ: CFBundleVersion=0.0.0-DEV の artifact を期待値なしで検証すると WARN + exit 0。
# Given: artifact の CFBundleVersion=0.0.0-DEV
fx6="$TMP_ROOT/uc6"; mkdir -p "$fx6"
zip6=$(make_app_zip "$fx6" "0.0.0-DEV")

# When: 期待値なしで release_artifact_validator.sh を実行する
set +e
out6=$(bash "$LIB" "$zip6" 2>&1)
rc6=$?
set -e

# Then: 終了コード 0
assert_status 0 "$rc6" "UC6-S1: 0.0.0-DEV + 期待値なしで終了コード 0"
# And (Then): WARN メッセージが出る
assert_grep "WARN.*0.0.0-DEV" "$out6" "UC6-S1: 0.0.0-DEV WARN メッセージ"
# And (Then): OK サマリで完了
assert_grep "release_artifact_validator: OK" "$out6" "UC6-S1: 0.0.0-DEV でも OK サマリ"

# シナリオ: CFBundleVersion=0.0.0-DEV の artifact を期待値 v1.0.0 で検証すると NG。
# Given: artifact の CFBundleVersion=0.0.0-DEV、期待値 v1.0.0
# When: 期待値ありで実行する
set +e
out6b=$(bash "$LIB" "$zip6" "v1.0.0" 2>&1)
rc6b=$?
set -e
# Then: 終了コード 1（CI 厳格化経路）
assert_status 1 "$rc6b" "UC6-S2: 0.0.0-DEV + 期待値ありで終了コード 1"
# And (Then): mismatch メッセージ
assert_grep "NG.*CFBundleVersion mismatch" "$out6b" "UC6-S2: mismatch NG"

# ===== UC7: CFBundleExecutable と MacOS バイナリ名の整合性 =====
# ユースケース:
# Info.plist の CFBundleExecutable と Contents/MacOS の実バイナリ名が
# 一致しているかを検証する（プロセス起動失敗の事前検知）。

# シナリオ: CFBundleExecutable=MacHealth、Contents/MacOS/MacHealth ありで OK。
# Given: 正常 artifact
fx7="$TMP_ROOT/uc7"; mkdir -p "$fx7"
zip7=$(make_app_zip "$fx7" "v1.0.0")
# When: 検証する
set +e
out7=$(bash "$LIB" "$zip7" "v1.0.0" 2>&1)
rc7=$?
set -e
# Then: 整合性 OK 行が出る
assert_status 0 "$rc7" "UC7-S1: 正常整合で終了コード 0"
assert_grep "OK.*CFBundleExecutable 'MacHealth' aligns" "$out7" "UC7-S1: CFBundleExecutable 整合 OK"

# シナリオ: CFBundleExecutable=Foo、Contents/MacOS/MacHealth のみ（不整合）で NG。
# Given: CFBundleExecutable だけ書き換えた artifact
fx7b="$TMP_ROOT/uc7b"; mkdir -p "$fx7b"
app7b="$fx7b/MacHealth.app"
mkdir -p "$app7b/Contents/MacOS" "$app7b/Contents/Resources"
cat > "$app7b/Contents/MacOS/MacHealth" <<'EOS'
#!/bin/bash
echo "uc7b"
EOS
chmod +x "$app7b/Contents/MacOS/MacHealth"
cp "$SRC_PLIST" "$app7b/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion v1.0.0" "$app7b/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable Foo" "$app7b/Contents/Info.plist" >/dev/null
(cd "$fx7b" && zip -r -q MacHealth-v1.0.0.zip MacHealth.app)
zip7b="$fx7b/MacHealth-v1.0.0.zip"
# When: 検証する
set +e
out7b=$(bash "$LIB" "$zip7b" "v1.0.0" 2>&1)
rc7b=$?
set -e
# Then: 終了コード 1
assert_status 1 "$rc7b" "UC7-S2: 不整合で終了コード 1"
# And (Then): no matching MacOS/Foo NG メッセージ
assert_grep "NG.*CFBundleExecutable 'Foo' has no matching MacOS/Foo" "$out7b" "UC7-S2: 不整合 NG メッセージ"

# ===== UC8: 期待値を引数 $3（repo-dir）経由で自動解決 =====
# ユースケース:
# 期待値を直接渡さなくても、第 3 引数で git リポジトリのルートを渡せば
# `git describe --tags --always` 値を期待値として解決する（CI / ローカル 両用）。

# シナリオ: 本リポジトリの git describe 値と一致する artifact を repo_dir 経由で検証 → OK。
# Given: 本リポジトリで git describe --tags --always を取得した値を CFBundleVersion とする artifact
expected_real=$(git -C "$REPO_DIR" describe --tags --always 2>/dev/null || echo "0.0.0-DEV")
fx8="$TMP_ROOT/uc8"; mkdir -p "$fx8"
zip8=$(make_app_zip "$fx8" "$expected_real")

# When: 期待値を渡さず、repo_dir のみ渡す
set +e
out8=$(bash "$LIB" "$zip8" "" "$REPO_DIR" 2>&1)
rc8=$?
set -e

# Then: 終了コード 0
assert_status 0 "$rc8" "UC8-S1: repo_dir 経由の期待値解決で終了コード 0"
# And (Then): CFBundleVersion matches expected 行が出る
assert_grep "OK.*CFBundleVersion matches expected" "$out8" "UC8-S1: 自動解決した期待値で一致 OK"

# --- 集計 ---
echo ""
echo "release_artifact_validator_test: $PASS passed, $FAIL failed"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
exit 0
