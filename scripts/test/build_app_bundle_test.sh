#!/bin/bash
# Mac Health Keeper - build_app_bundle.sh の単体テスト
#
# issue: 20260529_122727_Makefile_app化拡張（D331DD8F-C57D-4869-B6FF-B46CAB8E6F60）
#
# `scripts/lib/build_app_bundle.sh` の機能群（引数バリデーション・.app 構造組み立て・
# CFBundleVersion stamp 経路）と Makefile build / install.sh 経路との整合性を、
# 一時 fixture を作って BDD 形式で検証する。
#
# BDD 形式（ユースケース → シナリオ → Given/When/Then）は .agents/TEST_BDD_FORMAT.md に従う。
# 01_要件定義.md UC1-S1, UC1-S2, UC2-S1, UC3-S1 + 03_実装計画.md タスク 1/2/3/5/6/7 に対応。
# `make test-shell` から呼ばれ、失敗が 1 件でもあれば非 0 終了する。
# 破壊的副作用なし（mktemp で作成した一時ディレクトリで完結）。
#
# ユースケース全体（このテストファイルが守る不変条件）:
# `scripts/lib/build_app_bundle.sh` が、ビルド済みバイナリと Info.plist テンプレから
# macOS の `.app` ディレクトリ構造を組み立て、必要に応じて version_stamp.sh で
# CFBundleVersion を git describe 由来の値に上書きできること。Makefile build 経路と
# install.sh 経路の両方で同等の `.app` を再現できることを保証する。

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO_DIR/scripts/lib/build_app_bundle.sh"
STAMP_LIB="$REPO_DIR/scripts/lib/version_stamp.sh"
SRC_PLIST="$REPO_DIR/src/Info.plist"

PASS=0
FAIL=0

# --- 自前 assert ヘルパ（shallow_clone_guard_test.sh と同流儀） ---

assert_status() {
  local expected="$1" actual="$2" msg="$3"
  if [ "$actual" -eq "$expected" ]; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (expected status $expected, got $actual)"
  fi
}

assert_eq() {
  local expected="$1" actual="$2" msg="$3"
  if [ "$actual" = "$expected" ]; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (expected '$expected', got '$actual')"
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

assert_executable() {
  local path="$1" msg="$2"
  if [ -x "$path" ]; then
    PASS=$((PASS + 1)); echo "  ok   - $msg"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - $msg (not executable: $path)"
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

# 前提
if [ ! -x "$LIB" ] && [ ! -f "$LIB" ]; then
  echo "FAIL: build_app_bundle.sh not found: $LIB" >&2
  exit 1
fi
if [ ! -f "$STAMP_LIB" ]; then
  echo "FAIL: version_stamp.sh not found: $STAMP_LIB" >&2
  exit 1
fi
if [ ! -f "$SRC_PLIST" ]; then
  echo "FAIL: src/Info.plist not found: $SRC_PLIST" >&2
  exit 1
fi
if ! command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
  # PlistBuddy はパスで直接叩く（command -v は通らないが exec できる）。
  # 念のため -e で確認する。
  if [ ! -x /usr/libexec/PlistBuddy ]; then
    echo "FAIL: PlistBuddy not found (macOS 必須)" >&2
    exit 1
  fi
fi

TMP_ROOT=$(mktemp -d -t mac-health-build-app-bundle.XXXXXX)
trap 'rm -rf "$TMP_ROOT"' EXIT

# ヘルパ: 1 ケースごとに clean な fixture を返す
make_fixture() {
  local dir="$1"
  mkdir -p "$dir"
  # ダミーバイナリ（chmod +x 付き）
  cat > "$dir/MacHealth" <<'EOS'
#!/bin/bash
echo "MacHealth dummy"
EOS
  chmod +x "$dir/MacHealth"
  # Info.plist テンプレ（src/Info.plist をコピー）
  cp "$SRC_PLIST" "$dir/Info.plist"
}

# ===== UC1: 正常系（引数 3 件 + REPO_DIR）で .app 構造 + stamp 完了 =====
# ユースケース:
# 通常 commit の REPO_DIR を渡したとき、build_app_bundle.sh が .app 骨格を作り、
# CFBundleVersion を `git describe --tags --always` の出力で上書きすること
# （01 UC1-S1）。

# シナリオ: 正常系で .app 構造が生成され、stamp された CFBundleVersion が
# `git describe --tags --always` と一致する。
# Given: ダミーバイナリと Info.plist テンプレ + 通常 git リポジトリ REPO_DIR
fx1="$TMP_ROOT/uc1"
make_fixture "$fx1"
out_app1="$TMP_ROOT/out1/MacHealth.app"
mkdir -p "$TMP_ROOT/out1"

# When: build_app_bundle.sh を引数 4 件で実行する
set +e
out1=$(bash "$LIB" "$fx1/MacHealth" "$fx1/Info.plist" "$out_app1" "$REPO_DIR" 2>&1)
rc1=$?
set -e

# Then: 終了コード 0 で完了する
assert_status 0 "$rc1" "UC1-S1: 正常系で終了コード 0"
# And (Then): .app/Contents/MacOS/MacHealth が実行可能ファイルとして存在する
assert_executable "$out_app1/Contents/MacOS/MacHealth" "UC1-S1: MacHealth が executable で存在"
# And (Then): .app/Contents/Info.plist が存在する
assert_file_exists "$out_app1/Contents/Info.plist" "UC1-S1: Info.plist が存在"
# And (Then): Resources/ ディレクトリも作られている
assert_dir_exists "$out_app1/Contents/Resources" "UC1-S1: Resources/ ディレクトリが存在"
# And (Then): CFBundleVersion が `git describe --tags --always` と一致
expected1=$(git -C "$REPO_DIR" describe --tags --always 2>/dev/null)
actual1=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$out_app1/Contents/Info.plist" 2>/dev/null)
assert_eq "$expected1" "$actual1" "UC1-S1: CFBundleVersion が git describe と一致"
# And (Then): stdout の最終行に注入値が出る（CI ログ追跡用）
assert_grep "$expected1" "$out1" "UC1-S1: stdout に注入値が出力される"

# ===== UC2: Info.plist 必須キーの保持 =====
# ユースケース:
# build_app_bundle.sh の cp 後に Info.plist の必須キー（AppBundlePolicy 準拠）が
# 全て保持されていること（key を落とさないことの回帰検知）。

# シナリオ: 正常系で生成された .app の Info.plist に必須キーが全て揃っている。
# Given: UC1-S1 で生成された .app の Info.plist
# When: PlistBuddy で各キーを抽出する
plist1="$out_app1/Contents/Info.plist"
get_key() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$plist1" 2>/dev/null || echo ""
}

# Then: 6 つの必須キー（AppBundlePolicy.requiredInfoPlistKeys 相当）が全て非空
for key in CFBundleExecutable CFBundleIdentifier CFBundleName CFBundlePackageType CFBundleVersion CFBundleShortVersionString; do
  val=$(get_key "$key")
  if [ -n "$val" ]; then
    PASS=$((PASS + 1)); echo "  ok   - UC2-S1: 必須キー $key が非空 ($val)"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL - UC2-S1: 必須キー $key が空 / 不在"
  fi
done

# シナリオ: CFBundleExecutable が "MacHealth" であり、Contents/MacOS の実行ファイル名と一致する。
# Given: 上記 .app
# When: CFBundleExecutable を読み、対応する Contents/MacOS/<name> の存在を確認
exe_name=$(get_key CFBundleExecutable)
# Then: Contents/MacOS/<exe_name> が executable で存在する
assert_executable "$out_app1/Contents/MacOS/$exe_name" "UC2-S2: CFBundleExecutable と MacOS/<exe> 名が一致"

# ===== UC3: 引数不足の異常系 =====
# ユースケース:
# build_app_bundle.sh は引数欠落に対して usage 表示 + 終了コード 2 で明確に失敗し、
# サイレント成功しない（CI / ローカルで誤呼び出しを即検知する契約）。

# シナリオ: 引数を 1 件も渡さないと終了コード 2 と Usage を stderr に出す。
# Given: 引数 0 件呼び出し
# When: bash build_app_bundle.sh を引数なしで実行する
set +e
err2=$(bash "$LIB" 2>&1 >/dev/null)
rc2=$?
set -e
# Then: 終了コード 2
assert_status 2 "$rc2" "UC3-S1: 引数 0 件で終了コード 2"
# And (Then): Usage を含むエラー出力
assert_grep "Usage:" "$err2" "UC3-S1: Usage が出力される"

# シナリオ: 引数 2 件（末尾欠落）でも終了コード 2 + Usage。
# Given: 引数 2 件
# When: bash build_app_bundle.sh <bin> <plist> のみで実行する
set +e
err3=$(bash "$LIB" "$fx1/MacHealth" "$fx1/Info.plist" 2>&1 >/dev/null)
rc3=$?
set -e
# Then: 終了コード 2 + Usage
assert_status 2 "$rc3" "UC3-S2: 引数 2 件で終了コード 2"
assert_grep "Usage:" "$err3" "UC3-S2: 引数 2 件でも Usage 出力"

# ===== UC4: 入力ファイル不在の異常系 =====
# ユースケース:
# 引数で指定された binary / Info.plist が存在しない場合、cp を試みる前に
# 明確なエラーメッセージで終了コード 1 を返す。

# シナリオ: バイナリが存在しないとき終了コード 1 + "binary not found"。
# Given: 存在しないバイナリパス + 正常な Info.plist + 出力 .app
fx4="$TMP_ROOT/uc4"
make_fixture "$fx4"
out_app4="$TMP_ROOT/out4/MacHealth.app"
# When: bash build_app_bundle.sh <missing-bin> <plist> <out.app> を実行する
set +e
err4=$(bash "$LIB" "$TMP_ROOT/does_not_exist_bin" "$fx4/Info.plist" "$out_app4" "$REPO_DIR" 2>&1 >/dev/null)
rc4=$?
set -e
# Then: 終了コード 1
assert_status 1 "$rc4" "UC4-S1: バイナリ不在で終了コード 1"
# And (Then): エラーメッセージに "binary not found"
assert_grep "binary not found" "$err4" "UC4-S1: binary not found エラー"

# シナリオ: Info.plist が存在しないとき終了コード 1 + "info-plist-src not found"。
# Given: 正常なバイナリ + 存在しない Info.plist パス
fx5="$TMP_ROOT/uc4-2"
make_fixture "$fx5"
out_app5="$TMP_ROOT/out4-2/MacHealth.app"
# When: bash build_app_bundle.sh を実行する
set +e
err5=$(bash "$LIB" "$fx5/MacHealth" "$TMP_ROOT/does_not_exist.plist" "$out_app5" "$REPO_DIR" 2>&1 >/dev/null)
rc5=$?
set -e
# Then: 終了コード 1
assert_status 1 "$rc5" "UC4-S2: Info.plist 不在で終了コード 1"
# And (Then): エラーメッセージに "info-plist-src not found"
assert_grep "info-plist-src not found" "$err5" "UC4-S2: info-plist-src not found エラー"

# ===== UC5: 出力 .app の拡張子チェック =====
# ユースケース:
# 出力先パスは必ず `.app` で終わる（macOS Bundle Programming Guide の慣習）。

# シナリオ: 拡張子なしの出力パスを指定すると終了コード 1 で拒否する。
# Given: 拡張子なしの出力パス
fx6="$TMP_ROOT/uc5"
make_fixture "$fx6"
out_no_ext="$TMP_ROOT/out5/MacHealth"
# When: build_app_bundle.sh を実行する
set +e
err6=$(bash "$LIB" "$fx6/MacHealth" "$fx6/Info.plist" "$out_no_ext" "$REPO_DIR" 2>&1 >/dev/null)
rc6=$?
set -e
# Then: 終了コード 1
assert_status 1 "$rc6" "UC5-S1: 拡張子なしで終了コード 1"
# And (Then): エラーメッセージに ".app" の文字列
assert_grep "\.app" "$err6" "UC5-S1: .app 必須エラーメッセージ"

# ===== UC6: stamp 経路の skip（REPO_DIR が空） =====
# ユースケース:
# 第 4 引数も REPO_DIR 環境変数も渡されなかった場合、version_stamp.sh の
# 呼び出しを skip し、Info.plist テンプレの値（典型は 0.0.0-DEV）のまま .app 構造のみ作成する。
# 非 git 環境の CI で本スクリプトを呼ぶケースの保険。

# シナリオ: 引数 3 件のみ + REPO_DIR 環境変数なしで .app は作られるが stamp は走らない。
# Given: 引数 3 件のみ呼び出し + 環境変数 REPO_DIR を unset
fx7="$TMP_ROOT/uc6"
make_fixture "$fx7"
out_app7="$TMP_ROOT/out6/MacHealth.app"
# When: env -u REPO_DIR bash build_app_bundle.sh <bin> <plist> <out.app> を実行する
set +e
out7=$(env -u REPO_DIR bash "$LIB" "$fx7/MacHealth" "$fx7/Info.plist" "$out_app7" 2>&1)
rc7=$?
set -e
# Then: 終了コード 0 で完了する
assert_status 0 "$rc7" "UC6-S1: REPO_DIR なしでも終了コード 0"
# And (Then): .app 構造は作られる
assert_executable "$out_app7/Contents/MacOS/MacHealth" "UC6-S1: stamp skip でも MacHealth 配置完了"
assert_file_exists "$out_app7/Contents/Info.plist" "UC6-S1: stamp skip でも Info.plist 配置完了"
# And (Then): CFBundleVersion は Info.plist テンプレの初期値 0.0.0-DEV のまま
val7=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$out_app7/Contents/Info.plist" 2>/dev/null)
assert_eq "0.0.0-DEV" "$val7" "UC6-S1: stamp skip 時は CFBundleVersion=0.0.0-DEV のまま"
# And (Then): stdout には注入値が流れない（stamp 経路に入っていない契約）
if printf '%s' "$out7" | grep -q "$expected1"; then
  FAIL=$((FAIL + 1)); echo "  FAIL - UC6-S1: stamp skip なのに stdout に注入値が出ている"
else
  PASS=$((PASS + 1)); echo "  ok   - UC6-S1: stamp skip 時は stdout に注入値を出さない"
fi

# ===== UC7: Makefile build と install.sh で生成された .app が同等であること =====
# ユースケース:
# build_app_bundle.sh を共通化したことで、Makefile build 経路と install.sh 経路の
# 双方で生成される .app の構造・CFBundleVersion が一致すること（共通化の本質的価値）。
# 本テストでは「同じ引数で呼ぶと同じ Info.plist になる」を一時 fixture で再現する。

# シナリオ: 同一 REPO_DIR / 同一 Info.plist テンプレで 2 回呼ぶと CFBundleVersion が一致。
# Given: 2 つの fixture（バイナリは別物だが Info.plist と REPO_DIR は同じ）
fx8a="$TMP_ROOT/uc7a"
fx8b="$TMP_ROOT/uc7b"
make_fixture "$fx8a"
make_fixture "$fx8b"
out_app8a="$TMP_ROOT/out7a/MacHealth.app"
out_app8b="$TMP_ROOT/out7b/MacHealth.app"
# When: それぞれ build_app_bundle.sh を呼ぶ
set +e
bash "$LIB" "$fx8a/MacHealth" "$fx8a/Info.plist" "$out_app8a" "$REPO_DIR" >/dev/null 2>&1
rc8a=$?
bash "$LIB" "$fx8b/MacHealth" "$fx8b/Info.plist" "$out_app8b" "$REPO_DIR" >/dev/null 2>&1
rc8b=$?
set -e
# Then: 2 回とも終了コード 0
assert_status 0 "$rc8a" "UC7-S1: 1 回目 終了コード 0"
assert_status 0 "$rc8b" "UC7-S1: 2 回目 終了コード 0"
# And (Then): 2 つの CFBundleVersion が一致
v8a=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$out_app8a/Contents/Info.plist" 2>/dev/null)
v8b=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$out_app8b/Contents/Info.plist" 2>/dev/null)
assert_eq "$v8a" "$v8b" "UC7-S1: Makefile/install.sh 経路で CFBundleVersion が一致"
# And (Then): 一致した値は git describe と一致
expected8=$(git -C "$REPO_DIR" describe --tags --always 2>/dev/null)
assert_eq "$expected8" "$v8a" "UC7-S1: 一致値が git describe と一致"

# ===== UC8: 上書きビルド（既存 .app に対する 2 回目呼び出し） =====
# ユースケース:
# 同じ出力先に対して再度 build_app_bundle.sh を呼ぶと、Contents/MacOS のバイナリが
# 上書きされ、Info.plist も再度 stamp される（CI でのキャッシュ温存 + 上書き運用）。

# シナリオ: 既存 .app に対し別バイナリで上書きすると、Contents/MacOS のサイズが更新される。
# Given: 既に UC1 で作った out_app1 に対して、サイズの違う 2 番目のダミーバイナリを用意
size1_before=$(wc -c < "$out_app1/Contents/MacOS/MacHealth")
fx9="$TMP_ROOT/uc8"
mkdir -p "$fx9"
# 2 番目のダミーは echo を 5 回入れて元より大きく作る
cat > "$fx9/MacHealth" <<'EOS'
#!/bin/bash
echo "MacHealth v2 line 1"
echo "MacHealth v2 line 2"
echo "MacHealth v2 line 3"
echo "MacHealth v2 line 4"
echo "MacHealth v2 line 5"
EOS
chmod +x "$fx9/MacHealth"
cp "$SRC_PLIST" "$fx9/Info.plist"
# When: build_app_bundle.sh で同じ out_app1 を上書きする
set +e
bash "$LIB" "$fx9/MacHealth" "$fx9/Info.plist" "$out_app1" "$REPO_DIR" >/dev/null 2>&1
rc9=$?
set -e
# Then: 終了コード 0
assert_status 0 "$rc9" "UC8-S1: 既存 .app 上書きで終了コード 0"
# And (Then): Contents/MacOS のサイズが変化した（上書き成功の指標）
size1_after=$(wc -c < "$out_app1/Contents/MacOS/MacHealth")
if [ "$size1_before" != "$size1_after" ]; then
  PASS=$((PASS + 1)); echo "  ok   - UC8-S1: バイナリが上書きされた (before=$size1_before, after=$size1_after)"
else
  FAIL=$((FAIL + 1)); echo "  FAIL - UC8-S1: バイナリサイズが変化していない (size=$size1_before)"
fi
# And (Then): 上書き後の CFBundleVersion も再 stamp された（同じ HEAD なら同じ値）
v_after=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$out_app1/Contents/Info.plist" 2>/dev/null)
assert_eq "$expected1" "$v_after" "UC8-S1: 上書きビルドでも CFBundleVersion = git describe"

# ===== UC9: 実機経路相当 — REPO_DIR を渡せば src/Info.plist + 実バイナリで動く =====
# ユースケース:
# 実プロジェクトの src/Info.plist と build-bin で作ったバイナリ風（ここではダミー）に対して
# build_app_bundle.sh が一気通貫で動くこと（make build の sanity 確認）。

# シナリオ: src/Info.plist を直接テンプレに使い、REPO_DIR を本物にして呼ぶ。
# Given: 実 src/Info.plist + ダミーバイナリ + REPO_DIR=本物
fx10dir="$TMP_ROOT/uc9"
mkdir -p "$fx10dir"
cat > "$fx10dir/MacHealth" <<'EOS'
#!/bin/bash
echo "uc9 dummy"
EOS
chmod +x "$fx10dir/MacHealth"
out_app10="$TMP_ROOT/out9/MacHealth.app"
# When: build_app_bundle.sh を実 SRC_PLIST で呼ぶ（src/Info.plist は書き換えない）
src_plist_mtime_before=$(stat -f '%m' "$SRC_PLIST" 2>/dev/null || stat -c '%Y' "$SRC_PLIST" 2>/dev/null)
set +e
bash "$LIB" "$fx10dir/MacHealth" "$SRC_PLIST" "$out_app10" "$REPO_DIR" >/dev/null 2>&1
rc10=$?
set -e
src_plist_mtime_after=$(stat -f '%m' "$SRC_PLIST" 2>/dev/null || stat -c '%Y' "$SRC_PLIST" 2>/dev/null)
# Then: 終了コード 0
assert_status 0 "$rc10" "UC9-S1: 実 src/Info.plist テンプレで終了コード 0"
# And (Then): src/Info.plist の mtime が変化していない（テンプレ書き換え禁止の不変条件）
assert_eq "$src_plist_mtime_before" "$src_plist_mtime_after" "UC9-S1: src/Info.plist テンプレを書き換えていない"
# And (Then): out.app/Contents/Info.plist の CFBundleVersion は git describe と一致
v10=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$out_app10/Contents/Info.plist" 2>/dev/null)
assert_eq "$expected1" "$v10" "UC9-S1: 実テンプレ経路でも stamp 完了"

# --- 集計 ---
echo ""
echo "build_app_bundle_test: $PASS passed, $FAIL failed"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
exit 0
