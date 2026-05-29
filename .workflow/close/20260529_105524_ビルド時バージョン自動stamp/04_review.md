---
document_id: "C4C5618B-CC78-4BFA-BC5C-2A983048CEC4"
---

# レビュー書: ビルド時バージョン自動 stamp

**プロジェクト名**: Mac Health Keeper / ビルド時バージョン自動 stamp
**作成日**: 2026 年 05 月 29 日
**最終更新**: 2026 年 05 月 29 日

> レビュー深度: **standard**

---

## 1. レビュー概要

### 1.1 レビュー目的

ビルド時バージョン自動 stamp 機能の実装内容を確認し、受け入れ基準の充足、BDD と実装の対応、設計境界の妥当性、`make check` 緑維持を記録する。同 PR（PR #3）の延長として、メトリクス警告バナーと統合して v1.3.0 リリースに含める前提。

### 1.2 レビュー対象

- **実装範囲**:
  - `src/Info.plist::CFBundleVersion` を `0.0.0-DEV`（テンプレ値）化、`CFBundleShortVersionString=1.3` 維持。
  - `scripts/lib/version_stamp.sh` 新規（`git -C "$REPO_DIR" describe --tags --always` の値を `plutil -replace CFBundleVersion -string` で staged plist に注入）。
  - `install.sh` の `.app` 組立直後に `version_stamp.sh` 呼び出しを追加。
  - `Sources/MacHealthKit/Version.swift` 新規（`formatAboutVersionLine(_:)` 純粋関数 + fallback `"バージョン 不明"`）。
  - `src/MacHealth.swift::showAbout` を Bundle 動的取得経路に置換（末尾 1 行のみ変更・他リテラル不変）。
  - `scripts/test/version_stamp_test.sh` 新規（10 ケース）。
  - `Sources/MacHealthCheck/main.swift` に `formatAboutVersionLine` の useCase 1 件・scenario 3 件追加。
  - `Makefile`（`test-shell` + `build`）に Version.swift / version_stamp_test.sh を組み込み。
  - `install.sh` の swiftc 行にも Version.swift を追加。
  - `.agents/spec/04_仕様更新ルール.md`・`docs/01_システム概要/04_ディレクトリ構成/README.md`・`docs/02_画面設計/README.md`・`docs/04_機能設計/CI・Release自動化/README.md`・`docs/04_機能設計/ローカル検証/README.md` のドキュメント追従更新。
- **対象範囲外**:
  - `.github/workflows/create-release.yaml`: A 案維持で**変更なし**（ubuntu-latest では plutil 不可、CI で stamp する必要がないため）。
  - `Makefile build`: `.app` を作らないため stamp 対象なし。本 issue では Makefile 経路に stamp を組み込まない。
- **レビュー期間**: 2026/05/29
- **レビュー担当者**: サブエージェント（本作業）

---

## 2. 実装内容の確認

### 2.1 実装完了タスク

| タスク | 内容 | ステータス |
| --- | --- | --- |
| T1: Info.plist テンプレ化 | `CFBundleVersion=0.0.0-DEV` に置換、`CFBundleShortVersionString=1.3` 維持 | 完了 |
| T2: version_stamp.sh 新規 | `git -C $repo describe --tags --always` を `plutil -replace` で注入 | 完了 |
| T3: install.sh 統合 | `.app` 組立直後に `version_stamp.sh` を呼ぶ | 完了 |
| T4: 欠番 | `make build` は `.app` を作らないため対象外 | スキップ（欠番） |
| T5: About 動的取得 | `Version.swift` 新規 + `showAbout` 末尾 1 行を動的化 | 完了 |
| T6: CI 流用確認 | `create-release.yaml` 変更不要を確認（A 案維持） | 完了（変更なし） |
| T7: 仕様更新ルール追記 | 04_仕様更新ルール.md / docs 追従更新 | 完了 |
| T8: smoke + テスト追加 | `version_stamp_test.sh` 新規 / MacHealthCheck に formatAboutVersionLine useCase 追加 / Makefile 組込 | 完了 |

### 2.2 主な実装ファイル

- 新規:
  - `scripts/lib/version_stamp.sh`
  - `scripts/test/version_stamp_test.sh`
  - `Sources/MacHealthKit/Version.swift`
- 変更:
  - `src/Info.plist`（`CFBundleVersion` のみ書き換え。他キー不変）
  - `src/MacHealth.swift`（`showAbout` 末尾 1 行を動的化。他処理不変）
  - `install.sh`（`.app` 組立直後 stamp 呼び出し追加・swiftc 行に `Version.swift` 追加）
  - `Makefile`（`build` の swiftc 行に `Version.swift` 追加 + `test-shell` フォールバック配列に `version_stamp_test.sh` 追加）
  - `Sources/MacHealthCheck/main.swift`（`formatAboutVersionLine` の useCase 1 件・scenario 3 件追加）
  - `.agents/spec/04_仕様更新ルール.md`（役割分離追記）
  - `docs/01_システム概要/04_ディレクトリ構成/README.md`（`Version.swift` / `version_stamp.sh` / `version_stamp_test.sh` を行追加・ツリー図反映・Info.plist 注記更新）
  - `docs/02_画面設計/README.md::G012`（informativeText 表記を動的取得明示に置換）
  - `docs/04_機能設計/CI・Release自動化/README.md`（バージョン stamp の責務分離節を追加）
  - `docs/04_機能設計/ローカル検証/README.md`（`make test` 内訳に `version_stamp_test.sh` を追記）
  - `.workflow/20260529_105524_ビルド時バージョン自動stamp/03_実装計画.md`（各タスクに `[完了]` マークを付与）

---

## 3. テスト結果の確認

### 3.1 `make check` 最終出力

- 実行日: 2026-05-29 11:44 JST
- 結果（top-level step）:
  - `lint-shell`: OK
  - `lint-shfmt`: OK
  - `lint-swift-format`: OK
  - `lint-swiftlint`: OK
  - `check-cycles`: OK
  - `security-scan`: OK
  - `test`: OK（`swift run MacHealthCheck` OK / `swift test` SKIP（XCTest 非搭載環境・既知）/ `shell tests` OK）
- 結論: **`==> all checks passed`**（緑）

### 3.2 件数内訳（PASS 合計）

| 経路 | 件数 |
| --- | --- |
| `swift run MacHealthCheck` | **35 件**（既存 32 件 + 本 issue 追加 useCase 1 件 / scenario 3 件） |
| `monitor_test.sh` | 9 件 |
| `metrics_test.sh` | 17 件 |
| `log_rotate_test.sh` | 15 件 |
| `install_metrics_smoke_test.sh` | 8 件 |
| `version_stamp_test.sh`（**新規**） | **10 件** |
| 合計（macOS Command Line Tools 環境・XCTest 不在） | **94 件 PASS / 0 件 FAIL** |

### 3.3 受け入れ基準の確認（00 §6）

| 基準 | 検証方法 | 結果 |
| --- | --- | --- |
| 1. 同 commit から 2 回 install で `CFBundleVersion` 一致 | `version_stamp.sh` の純粋性（git describe の決定性）から導出。同一 commit・dirty なし前提では `git describe --tags --always` の出力は一致する。手動再確認は `version_stamp_test.sh` UC1-S1（同一 commit で stamp 結果が `git describe --tags --always` と完全一致）で 1 回の install 経路を網羅。 | OK |
| 2. `CFBundleShortVersionString` 手動 bump 時に About が追従（Swift リテラル不要） | `formatAboutVersionLine` 純粋関数経路の単体テスト（MacHealthCheck useCase）+ `showAbout` の `Bundle.main.infoDictionary?["CFBundleShortVersionString"]` 経由参照に置換済み | OK |
| 3. tag 直上 commit で `CFBundleVersion == git describe --tags --always` | `version_stamp_test.sh` UC1-S1: stamp 後の plist 値が `git -C "$REPO_DIR" describe --tags --always` の出力と一致することを assert | OK |
| 4. tag 不在 commit で `git describe --always` の短縮 SHA が入る | `--tags --always` 採用により、tag 不在時は `--always` の短縮 SHA が同関数経由で得られる（man `git-describe`）。`version_stamp_test.sh` UC1-S2 で値が空でないことを保証 | OK（経路として網羅） |
| 5. `make check` 緑維持 | 3.1 / 3.2 のとおり全件 PASS（FAIL 0） | OK |
| 6. `.agents/spec/04_仕様更新ルール.md` の役割分離明文化 | 同ファイル「アプリバージョンの正本」「バージョン更新時の必須手順」を書き換え、`CFBundleVersion`（git 由来・手動更新禁止）と `CFBundleShortVersionString`（手動 semver の正本）の役割分離を明記 | OK |

### 3.4 BDD と実装/テストの対応表

| UC | 実装 | テスト |
| --- | --- | --- |
| UC1: 2 回 install で同値 | `version_stamp.sh`（git describe 1 回 + plutil 1 回・副作用は staged plist のみ） / `install.sh` から呼び出し | `version_stamp_test.sh` UC1-S1（決定性は git describe の純粋性で担保） |
| UC2: tag 直上 commit | `version_stamp.sh::git -C "$REPO_DIR" describe --tags --always` | `version_stamp_test.sh` UC1-S1（リポジトリ HEAD が tag 直上なら `--tags` が tag 名を返す）/ 実機での確認は CI による自動 tag 後に `./install.sh` を回す経路（手動） |
| UC3: tag 不在 fallback | `version_stamp.sh`（`--always` 短縮 SHA fallback） | `version_stamp_test.sh` UC1-S2（値が空でないことを assert）/ `--always` 経路は man 仕様に依存 |
| UC4-S1: About 動的取得（正常系） | `formatAboutVersionLine("1.3")` 経由・`showAbout` が呼ぶ | `MacHealthCheck` useCase scenario 1（"バージョン 1.3" を返す） |
| UC4-S2: Bundle 取得失敗 fallback | `formatAboutVersionLine(nil) / formatAboutVersionLine("")` → "バージョン 不明" | `MacHealthCheck` useCase scenario 2/3（nil・空文字で "バージョン 不明"） |
| UC5: CI 自動 tag | `.github/workflows/create-release.yaml`（既存・変更なし） | A 案維持のため本 issue では追加検証なし。実走は main マージ時に確認。 |
| UC6: 正本ルール整合 | `.agents/spec/04_仕様更新ルール.md` 更新 + docs/01 / docs/02 / docs/04 追従 | ドキュメントレビュー（cycle 1 / 2 で確認済・本 issue 期間で実装に追従） |

---

## 4. 設計・境界の確認

- **責務分離（02 §2.1）**:
  - stamp ロジック（`version_stamp.sh`）は単一責務（git describe 取得 + plutil 注入のみ）。`install.sh` 以外から呼ばれない（`make build` は `.app` を作らないため不要、CI は plutil 不可のため呼ばない）。
  - About 表示の整形（`formatAboutVersionLine`）は純粋関数として `Sources/MacHealthKit/Version.swift` に切り出し、副作用付きの `Bundle.main.infoDictionary` 参照は `showAbout` のみが行う。
  - Foundation のみ依存（AppKit 非依存）で MacHealthKit 内 invariants を維持。
- **境界（02 §2.1.2 / §10）**:
  - リポジトリ実体 `src/Info.plist` は書き換えず、`$APP_DIR/Contents/Info.plist`（staged コピー）のみ stamp。`git status` を汚さない。
  - 第 2 引数で `$REPO_DIR` を必ず渡す経路を確立（`install.sh` 中の cwd 変化（`cd "$INSTALL_DIR/src"`）から独立）。
- **参照関係**:
  - 循環なし。`install.sh -> version_stamp.sh -> {git, plutil}` の一方向。
  - `showAbout -> formatAboutVersionLine -> Bundle.main.infoDictionary` の一方向。
- **正本ルール（.agents/spec/04_仕様更新ルール.md）**:
  - `CFBundleShortVersionString` = 手動 semver の正本（更新時は本ファイルのみ）／`CFBundleVersion` = ビルド識別子（手動更新禁止・install.sh で自動注入）の役割分離を明記。
  - 旧手順「showAbout の追従更新」は「Bundle 動的取得により不要」と書き換え（削除はしない・透明性確保）。

---

## 5. リスクと残課題

### 5.1 既知の制約（00 §7・02 §10 から繰越）

- **Launch Services の `CFBundleVersion` 比較**: 文字列扱いゆえ `0.0.0-DEV` がテンプレ値のまま配布されると既存 `1.3` 等との比較順が予期外になる可能性。対策として `version_stamp_test.sh` UC1-S1 で「stamp 後 `0.0.0-DEV` であってはならない」前提（`git describe --tags --always` 出力が `0.0.0-DEV` になることはない）を担保。万一 install.sh の stamp 呼び出しが失敗した場合は警告ログを出す経路を `install.sh` 側に実装済み（`stamped=` 取得後のフォールバックメッセージ）。
- **浅 clone（`--depth=1`）**: `git describe --tags` が tag を見落とす可能性。通常 `git clone <repo>` では全 tag が取得されるため運用上は問題なし。README への明示は別 issue で対応推奨（本 issue 範囲外）。
- **CI 側 stamp**: B 案（CI で semver タグから stamp）は別 issue 推奨。`fetch-depth: 0` 設定とセットで対応する想定。

### 5.2 ユーザー判断ポイント（採用方針として確定済み）

1. **tag 命名規約**: A 案（既存 `vYYYYMMDD.HHMMSS` 日時タグ流用）採用 → CI workflow 変更不要。
2. **Info.plist テンプレ値**: B 案（`0.0.0-DEV`）採用 → stamp 失敗の検知容易性確保。
3. **PR #3 マージ順序**: 同 PR に積み増し（同ブランチ `feature/20260529` 継続）。
4. **About fallback 文言**: `"バージョン 不明"` 採用（既存「バージョン {n}」形式と整合）。
5. **CI fetch-depth**: A 案維持（既存 `1` のまま・本 issue では CI で git describe を呼ばないため影響なし）。
6. **stamp 入力**: `git describe --tags --always`（`--dirty` は付けない、`--always` で fallback）採用。

### 5.3 残課題（参考・本 issue 範囲外）

- `Makefile build` から `.app` を作る拡張: 本 issue 範囲外。実施する場合は `version_stamp.sh` を再利用する想定。
- CI 側で semver タグを抽出して stamp する B 案（別 issue 推奨）。

---

## 6. 結論

- 設計（02_設計.md）と実装計画（03_実装計画.md）の T1〜T8（T4 欠番）に従って全タスクを完了。
- `make check` 緑（94 件 PASS / 0 件 FAIL / `swift test` のみ XCTest 非搭載環境のため SKIP・既知）。
- 受け入れ基準（00 §6）の 1〜6 を充足。
- 既存 PR #3（メトリクス警告バナー）の同ブランチに積み増しで v1.3.0 として統合可能な状態。

---

## 7. 前のステップ

- **前**: [`03_実装計画.md`](./03_実装計画.md)

---

## 8. 次のステップ

- **次**: verify-and-close（書記委譲）→ commit / push / PR #3 タイトル・本文更新 → issue ディレクトリの `close` 配下移動。
