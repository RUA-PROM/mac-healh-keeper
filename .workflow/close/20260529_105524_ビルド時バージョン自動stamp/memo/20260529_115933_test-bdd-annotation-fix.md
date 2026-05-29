---
document_id: "004F2255-92B2-46DB-969A-7C64CBD0AE21"
---

# テスト BDD 注釈不足の追補（version_stamp_test.sh ほか）

- 作成日時: 2026-05-29 11:59:33 (JST)
- 親 issue: `.workflow/close/20260529_105524_ビルド時バージョン自動stamp/`
- 関連 issue: `.workflow/close/20260529_083530_メトリクス非表示修正/`
- 関連 PR: #3（feature/20260529）

---

## 1. 背景

ユーザーから「`scripts/test/version_stamp_test.sh` に **ユースケース・シナリオ・Given/When/Then が無い**、agents には記載するよう明記されているはずだ。全テストを見直してほしい」との指摘を受けた。

直近の verify-and-close (`20260529_105524_ビルド時バージョン自動stamp`) で新規追加した
`scripts/test/version_stamp_test.sh` は、ヘッダの「目的」セクションに UC ラベルこそ並べていたものの、本文に規約（`.agents/TEST_BDD_FORMAT.md`）が要求する `ユースケース:` / `シナリオ:` doc コメントと、各テストブロック直上の `Given:` / `When:` / `Then:` インラインコメント形式を満たしていなかった。

## 2. 規約根拠

- `.agents/RULES.md` §テスト（L28）
  > テストコードでは、テストのまとまりごとに `ユースケース:`、各テストごとに `シナリオ:` を doc コメント（言語慣習に合うブロックコメント）で記載し、実行ブロックごとに Given / When / Then（必要に応じて And）をインラインコメントで必ず記載する（.agents/TEST_BDD_FORMAT.md）。監査で確認する。

- `.agents/RULES.md` §テスト戦略必須要件（L36）
  > **単体**: 正常系・異常系・境界値・回帰・結合を BDD（ユースケース・シナリオ・Given/When/Then/And インラインコメント）で網羅。未達時は理由を記載。

- `.agents/TEST_BDD_FORMAT.md` §0 必須レイヤー
  > **ユースケース**（テストのまとまり）／**シナリオ**（各テストメソッド）／**Given / When / Then**（各テスト本体）の 3 レイヤーをすべて満たす。この形を強制する。**禁止**: ユースケース・シナリオを省略する。Given/When/Then のみで済ませる。

- `.agents/TEST_BDD_FORMAT.md` §1 インラインコメント必須
  > **コメントは各ブロックの「直上」に 1 つだけ書く**。コメントだけをまとめて書いたり、ブロックと対応させない書き方は不可。

- `.agents/TEST_BDD_FORMAT.md` §3 01・03 との対応
  > テスト観点は 01_要件定義の BDD シナリオおよび 03_実装計画のタスク別テスト仕様と対応させる。

## 3. 棚卸し結果（テストファイル全件）

`Tests/MacHealthKitTests/`・`Sources/MacHealthCheck/`・`scripts/test/` を全件確認。

| ファイル | 状態 | 是正 |
|---|---|---|
| `Tests/MacHealthKitTests/AppleScriptEscaperTests.swift` | 良好 | 不要 |
| `Tests/MacHealthKitTests/JobCatalogTests.swift` | 良好 | 不要 |
| `Tests/MacHealthKitTests/JobControllerSafetyTests.swift` | 良好 | 不要 |
| `Tests/MacHealthKitTests/JobControllerTests.swift` | 良好 | 不要 |
| `Tests/MacHealthKitTests/LogOpenInvocationTests.swift` | 良好 | 不要 |
| `Tests/MacHealthKitTests/MenuModelTests.swift` | 警告バナー追加 UC の doc コメントが宙に浮く | 軽微（`// MARK` セクションの補助コメントへ降格） |
| `Tests/MacHealthKitTests/MetricsParserTests.swift` | 良好 | 不要 |
| `Tests/MacHealthKitTests/ScheduleTimingTests.swift` | 良好 | 不要 |
| `Tests/MacHealthKitTests/ShellRunnerContractTests.swift` | 良好 | 不要 |
| `Tests/MacHealthKitTests/SpyShellRunner.swift` | テストヘルパ | 対象外 |
| `Tests/MacHealthKitTests/ZshShellRunnerInjectionTests.swift` | 良好 | 不要 |
| `Sources/MacHealthCheck/main.swift` | 完全準拠（`useCase`/`scenario` DSL） | 不要 |
| `Sources/MacHealthCheck/TestRunner.swift` | ランナー基盤 | 対象外 |
| `scripts/test/monitor_test.sh` | 良好 | 不要 |
| `scripts/test/metrics_test.sh` | UC1 のユースケース doc のみ、UC2 / サブ F が無い | 追補 |
| `scripts/test/log_rotate_test.sh` | 良好 | 不要 |
| `scripts/test/install_metrics_smoke_test.sh` | UC コメントが「ユースケース:」ラベルに揃っていない | 形式統一 |
| `scripts/test/monitor.bats` | 良好 | 不要 |
| `scripts/test/metrics.bats` | UC1 のユースケース doc のみ、UC2 / サブ F が無い | 追補 |
| `scripts/test/log_rotate.bats` | 良好 | 不要 |
| **`scripts/test/version_stamp_test.sh`** | **UC/Scenario doc、Given/When/Then インラインなし** | **必須是正** |

備考: テストヘルパ（`SpyShellRunner.swift`）とランナー基盤（`TestRunner.swift`）はテスト「のまとまり」ではないため BDD 注釈の対象外。

## 4. 既存遵守例として参照したテンプレート

- **Shell（自前 assert ランナー）**: `scripts/test/monitor_test.sh`
  - ヘッダに `BDD 形式（ユースケース → シナリオ → Given/When/Then）は .agents/TEST_BDD_FORMAT.md に従う。` を明記
  - 続けて `# ユースケース:` 行（テスト全体のまとまり）
  - UC ごとに `# --- UC{N} ... ---` セクションヘッダ
  - 各 `setup()` 直後に `# シナリオ:` doc + `# Given:` / `# When:` / `# Then:` を各ブロック直上に置く
- **Shell（bats）**: `scripts/test/log_rotate.bats`（同じ流儀の `@test` ブロック版）
- **Swift（XCTest）**: `Tests/MacHealthKitTests/MenuModelTests.swift`（`/// ユースケース:` クラス doc + `/// シナリオ:` メソッド doc + 行コメント `// Given:` / `// When:` / `// Then:`）
- **Swift（pure-core ランナー）**: `Sources/MacHealthCheck/main.swift`（`useCase("...") { scenario("...") { ... } }` DSL）

## 5. 是正内容

### 5.1 `scripts/test/version_stamp_test.sh`（**主要是正**）

ヘッダの「目的」セクションに UC を箇条書きしていた状態から、規約準拠の `monitor_test.sh` と同じ流儀に書き直した。

- ヘッダに `BDD 形式（ユースケース → シナリオ → Given/When/Then）は .agents/TEST_BDD_FORMAT.md に従う。` を追記
- 対応 01: `.workflow/close/20260529_105524_ビルド時バージョン自動stamp/01_要件定義.md` UC1 と本ファイル固有の異常系（UC2 / UC3）を明記
- 自前 assert ヘルパに 1 行 doc コメント付与
- 各 UC のまとまり直前に `# ===== UC{N}: ... =====` + `# ユースケース: ...` doc コメント
- 各テストブロックに `# シナリオ: ...` doc + `# Given:` / `# When:` / `# Then:` / `# And (Then):` インラインコメント（各ブロック直上に 1 つ）
- 既存 assertion 内容は一切変更なし（`run_test` ランナー側の挙動も不変）

### 5.2 `scripts/test/metrics_test.sh`

- `# --- UC2 ... ---` セクション直下に `# ユースケース:` doc コメントを追補
- `# --- サブ F ... ---` セクション直下に `# ユースケース:` doc コメントを追補

### 5.3 `scripts/test/metrics.bats`

- `# --- UC2 ... ---` セクション直下に `# ユースケース:` doc コメントを追補
- `# --- サブ F ... ---` セクション直下に `# ユースケース:` doc コメントを追補

### 5.4 `scripts/test/install_metrics_smoke_test.sh`

- ヘッダの「目的・検証」セクションを、`.agents/TEST_BDD_FORMAT.md` 参照と 01 対応の明示に書き換え
- 既存の各 `# ===== ユースケース N: ... =====` セクションヘッダ直下を `# ユースケース:` doc コメント形式に統一（`UC1:` → `ユースケース:` 文体）

### 5.5 `Tests/MacHealthKitTests/MenuModelTests.swift`

- `// MARK: - 警告バナー` セクション内で宙に浮いていた `/// ユースケース:` doc コメントを、`// MARK` セクション補助の `//` 行コメントへ降格（Swift の `///` は宣言に紐付くため、宣言と紐付かない doc コメントは規約意図と乖離する）
- 内容自体は維持し、対応 issue（20260529_083530_メトリクス非表示修正）の参照を追記

## 6. 再発防止策

- **本 memo を `.agents/TEST_BDD_FORMAT.md` の運用事例として参照可能にする**: テスト追加時は本 memo の §5 を見本にする。
- **新規テストファイル追加時の自主チェック項目** を本 memo に明記：
  1. ヘッダに `BDD 形式（ユースケース → シナリオ → Given/When/Then）は .agents/TEST_BDD_FORMAT.md に従う。` を必ず記載
  2. 対応する 01_要件定義.md の UC / Scenario を明示
  3. テストのまとまり直前に `ユースケース:` doc コメント
  4. 各テスト直前に `シナリオ:` doc コメント
  5. 各実行ブロック直上に `Given:` / `When:` / `Then:`（必要に応じて `And:`）インラインコメント
- **verify-and-close の generate-scenarios / map-coverage で新規テストファイルにこのチェックを追加適用**: 既存 audit に「テスト本文の `ユースケース:` / `シナリオ:` / `Given:` / `When:` / `Then:` の有無」を加える。

## 7. `make check` 結果

実行: 2026-05-29 11:59:33 JST

```
==> all checks passed
MacHealthCheck: 35 passed, 0 failed
shell tests (monitor): 9 passed, 0 failed
metrics shell tests: 17 passed, 0 failed
log_rotate tests: 15 passed, 0 failed
install_metrics_smoke_test: 8 passed, 0 failed
version_stamp_test: 10 passed, 0 failed
合計: 94 passed, 0 failed（既存件数を維持）
```

## 8. 01_要件定義.md 側の整備

各テストが指す UC / シナリオは、既に対応する close 済み issue の `01_要件定義.md` に存在することを確認した（`version_stamp_test.sh` の UC1 = `20260529_105524_ビルド時バージョン自動stamp/01_要件定義.md §2.2 UC1`、`install_metrics_smoke_test.sh` の UC1〜UC3 = `20260529_083530_メトリクス非表示修正/01_要件定義.md` のフォロー smoke 観点）。

`version_stamp_test.sh` の UC2 / UC3 は 01 に直接対応するシナリオが無い（version_stamp.sh 個別の異常系契約）が、これは「ファイル固有の異常系テスト観点」として 03 系の派生テスト観点でカバーする扱いとし、テスト本体のコメントで「本ファイル固有の異常系」と明示した。close 済み 01 の改変は規約上の原則（過去確定 doc の不変）に反するため、本 memo を対応表とする。

## 9. ステージング・コミット

- ブランチ: `feature/20260529`
- 変更ファイル:
  - `scripts/test/version_stamp_test.sh`（書き直し）
  - `scripts/test/metrics_test.sh`（UC2 / サブ F に `ユースケース:` doc を追補）
  - `scripts/test/metrics.bats`（同上）
  - `scripts/test/install_metrics_smoke_test.sh`（ヘッダと UC コメント形式を統一）
  - `Tests/MacHealthKitTests/MenuModelTests.swift`（`/// ユースケース:` の降格）
  - `.workflow/close/20260529_105524_ビルド時バージョン自動stamp/memo/20260529_115933_test-bdd-annotation-fix.md`（本 memo）
- 個別ファイル指定で git add（`-A` / `.` 不使用）
- コミットメッセージ: `test: 既存テストに UC/Scenario/Given/When/Then 注釈を追補`
- `--no-verify` / `--amend` / `--force` 不使用

## 10. 残課題

- bats を環境にインストールすれば `metrics.bats` / `log_rotate.bats` / `monitor.bats` 経路もローカル CI で検証可能になる（任意・優先度低）。
- 監査自動化（テストファイルへの `ユースケース:` / `シナリオ:` / `Given:` / `When:` / `Then:` 存在チェック）は本 memo §6 で記載した方針に従い、後続 issue で `.agents/scripts/` 配下のヘルパに追加することを検討（本 issue 内では未実施）。
