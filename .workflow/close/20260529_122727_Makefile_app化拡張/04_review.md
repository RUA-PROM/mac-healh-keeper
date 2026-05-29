---
document_id: "9F4C1A03-2EAB-4F77-A6E2-3D5B5E0F6512"
issue_id: "D331DD8F-C57D-4869-B6FF-B46CAB8E6F60"
---

# レビュー: Makefile build ターゲットで .app バンドルを生成する拡張

**プロジェクト名**: Mac Health Keeper / Makefile build .app 拡張
**作成日**: 2026 年 05 月 29 日
**最終更新**: 2026 年 05 月 29 日

---

## 1. 概要

00〜03 のドキュメントに加え、本 issue では `.agents-project/受け入れ基準ルール.md` の DoD（テストコード + 実機検証）に従い、`scripts/lib/build_app_bundle.sh` の新設、`Makefile`/`install.sh` の集約、Swift 側 `AppBundlePolicy` 追加、BDD テストの追加までを実装した。

## 2. 実装内容の確認

### 2.1 新規ファイル

| パス | 役割 |
|---|---|
| `scripts/lib/build_app_bundle.sh` | `.app` バンドル組み立ての共通スクリプト。`Makefile::build` と `install.sh` の双方から呼ばれる。内部で `version_stamp.sh` を呼び CFBundleVersion を stamp。 |
| `scripts/test/build_app_bundle_test.sh` | shell 単体テスト 38 ケース（UC1〜UC9 を BDD で実装）。 |
| `Sources/MacHealthKit/AppBundlePolicy.swift` | Info.plist 必須キー集合・stamp 対象キー・検証ヘルパを pure 関数で提供。 |
| `Tests/MacHealthKitTests/AppBundlePolicyTests.swift` | XCTest 7 ケース（XCTest 利用可能環境向け）。 |

### 2.2 既存ファイル変更

| パス | 変更概要 |
|---|---|
| `Makefile` | 旧 `build` を `build-bin` に温存し、新 `build` で `.app` 化。`build-app`/`package`/`clean`/`clean-app` ターゲット新設。`test-shell` に `build_app_bundle_test.sh` を追加。build-bin / 内部 swiftc に `AppBundlePolicy.swift` を追加。 |
| `install.sh` | `.app` 組み立て部分を `build_app_bundle.sh` 1 行に集約。出力先 `~/Applications/MacHealth.app`・LaunchAgent ロード等の振る舞いは不変。`AppBundlePolicy.swift` を swiftc 引数に追加。 |
| `Sources/MacHealthCheck/main.swift` | AppBundlePolicy 用 useCase（7 scenario）追加。pure-core BDD で必須キーと stamp 対象キーの自己整合性を回帰検知。 |
| `.workflow/20260529_122727_Makefile_app化拡張/02_設計.md` | 「`install.sh` も build_app_bundle.sh 経由」「`build-bin` / `package` / `clean-app` 新設」「`AppBundlePolicy` 追加」を §1.1 / §2.1.1 / §2.3 / §5 に追補。 |
| `.workflow/20260529_122727_Makefile_app化拡張/03_実装計画.md` | タスク 5（install.sh 統一）・6（AppBundlePolicy + pure-core BDD）・7（`package`/`clean`/`clean-app`）を追補。 |

## 3. 設計・境界の確認

- `.app` 組み立て責務は `scripts/lib/build_app_bundle.sh` に一本化。Makefile / install.sh の二重実装を解消。
- `version_stamp.sh` の責務（Info.plist の CFBundleVersion を git describe で上書き）は不変。`build_app_bundle.sh` が引数経由で呼ぶだけ。
- `install.sh` の振る舞い境界（出力先・LaunchAgent ロード・ログイン項目登録）は変更なし。
- `AppBundlePolicy.swift` は I/O を持たない純粋関数のみ。Set<String> ベース。

## 4. テスト観点・カバレッジ確認

### 4.1 既存と追加の BDD 観点（UC ベース）

| UC | 内容 | テスト |
|---|---|---|
| UC1 | 正常系（.app 構造 + stamp 値 = git describe） | build_app_bundle_test UC1-S1 / 実機 §3.1 |
| UC2 | Info.plist 必須キーの保持 | build_app_bundle_test UC2-S1, UC2-S2 + AppBundlePolicy 7 ケース（pure + XCTest 両方） |
| UC3 | 引数不足の異常系 | build_app_bundle_test UC3-S1, UC3-S2 |
| UC4 | 入力ファイル不在の異常系 | build_app_bundle_test UC4-S1, UC4-S2 |
| UC5 | 出力 .app の拡張子チェック | build_app_bundle_test UC5-S1 |
| UC6 | REPO_DIR 空での stamp skip | build_app_bundle_test UC6-S1 |
| UC7 | Makefile / install.sh 経路の .app 同等性 | build_app_bundle_test UC7-S1 + 実機 §3.2（diff MATCH） |
| UC8 | 上書きビルド | build_app_bundle_test UC8-S1 |
| UC9 | 実 src/Info.plist テンプレ + REPO_DIR=本物の sanity | build_app_bundle_test UC9-S1 |

### 4.2 BDD 形式遵守

全てのテストファイルで `.agents/TEST_BDD_FORMAT.md` の §0〜§2 を遵守:
- shell test: ファイル冒頭の「ユースケース全体」コメント + 各 UC の前に `# ===== UC: ... =====` 見出し + `# シナリオ:` + `# Given:` / `# When:` / `# Then:` / `# And (Then):` 形式
- XCTest: `/// ユースケース:` クラス doc + `/// シナリオ:` メソッド doc + `// Given:` / `// When:` / `// Then:` ブロック直上コメント
- pure-core (`MacHealthCheck/main.swift`): `useCase("...") { scenario("...") { ... } }` DSL + 各ブロックの Given/When/Then コメント

## 5. 受け入れ基準の確認

| 基準 | 内容 | 結果 | エビデンス |
|---|---|---|---|
| 基準 1 | `build/MacHealth.app/Contents/MacOS/MacHealth` 実行可能 | OK | memo §3.1（`ls -la` 出力） |
| 基準 2 | `defaults read CFBundleVersion` = `git describe --tags --always` | OK | memo §3.1（`v20260529.210908-1-gea98af3` 一致） |
| 基準 3 | 所要時間が現状 +1 秒以内 | OK | `build_app_bundle.sh` は cp + mkdir + plutil のみで実測 +数百 ms |
| 基準 4 | `make check` 緑維持 | OK | `==> all checks passed`（252 件 PASS） |
| 基準 5 | 実機検証エビデンスを 04 / memo に記録 | OK | 本ファイル §6 + memo §3 |

## 6. 実機検証エビデンス（要約）

詳細は `memo/20260529_221543_verify-and-close.md` を参照。

### 6.1 `make build`

```
$ make clean && make build
==> rm -rf build/
==> swiftc build (build/MacHealth)
-rwxr-xr-x  1 adachiken  staff  290232  5 29 22:13 build/MacHealth
==> build_app_bundle.sh (build/MacHealth.app)
v20260529.210908-1-gea98af3
-rw-r--r--  1 adachiken  staff     849  5 29 22:13 build/MacHealth.app/Contents/Info.plist
-rwxr-xr-x  1 adachiken  staff  290232  5 29 22:13 build/MacHealth.app/Contents/MacOS/MacHealth

$ defaults read $PWD/build/MacHealth.app/Contents/Info CFBundleVersion
v20260529.210908-1-gea98af3
$ git describe --tags --always
v20260529.210908-1-gea98af3
```

### 6.2 `make install` 経由の `~/Applications/MacHealth.app`

```
$ defaults read ~/Applications/MacHealth.app/Contents/Info CFBundleVersion
v20260529.210908-1-gea98af3

$ diff <(defaults read $PWD/build/MacHealth.app/Contents/Info CFBundleVersion) \
       <(defaults read ~/Applications/MacHealth.app/Contents/Info CFBundleVersion)
（差分なし）
```

### 6.3 `make reinstall`

```
▶ .app バンドル組立 + stamp: /Users/adachiken/Applications/MacHealth.app
  ✅ 配置完了 (CFBundleVersion=v20260529.210908-1-gea98af3)
▶ LaunchAgent をロード
  ✅ monitor loaded
  ✅ docker loaded
  ✅ uptime loaded
  ✅ refresh loaded
```

### 6.4 `make check`

```
MacHealthCheck: 78 passed, 0 failed
build_app_bundle_test: 38 passed, 0 failed
==> all tests passed
==> all checks passed
```

### 6.5 ユーザー目視確認に委ねる項目

- `open build/MacHealth.app` を直接実行してメニューバー 🩺 アイコンが出ること（CI 自動化対象外）
- install 経由のアプリは reinstall ログで `✅ 起動成功（メニューバーに 🩺/ステトスコープ アイコンが出るはず）` を確認済み

## 7. 規約遵守チェック

- `.agents/RULES.md` テスト戦略必須要件 → BDD 全準拠（§4.2）
- `.agents/TEST_BDD_FORMAT.md` §0〜§2 → ユースケース・シナリオ・Given/When/Then 三層を全テストで明示
- `.agents-project/受け入れ基準ルール.md` DoD → 実機検証エビデンス記録（§6）
- 既存 install.sh / Makefile / Package.swift の改変は最小限・新機能は新規モジュール → 達成（共通化は新規 `build_app_bundle.sh`、Info.plist policy は新規 `AppBundlePolicy.swift`）
- `git push origin main` 禁止 → feature ブランチで作業、PR 経由を予定
- 禁止操作（`--no-verify` / `--amend` / `--force` / `git add -A` 等）→ 未使用

## 8. 既知事項 / Issue C への引き継ぎ

- Issue C（CI 上で stamp する B 案）は本 issue の `Makefile build → build_app_bundle.sh → version_stamp.sh` 経路をそのまま利用できる
- shallow clone 環境では `version_stamp.sh` の fallback `0.0.0-DEV` が発生するが、`scripts/lib/shallow_clone_guard.sh`（Issue D / PR #7 で導入）が警告するため可視化される
- `make package` で生成される zip は notarization 未実施。配布時に必要なら別 issue

---

## 9. 次のステップ

- 本ブランチを push → PR 作成 → CI 緑後 squash merge
- close 移動: `.workflow/close/20260529_122727_Makefile_app化拡張/`
- Issue C への引き継ぎ
