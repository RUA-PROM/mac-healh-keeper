# テスト規約遵守事項と 00〜03 追補方針 memo

- **作成日時（JST）**: 2026-05-29 20:48:31
- **issue ディレクトリ**: `.workflow/20260529_122242_LaunchAgentロード失敗調査と修正/`

## 1. 参照したテスト規約・README

- `.agents/RULES.md` §テスト / §テスト戦略必須要件
- `.agents/TEST_BDD_FORMAT.md`（§0 必須レイヤー、§1 インラインコメント必須、§2 And、§3 01・03 との対応）
- `.agents/workflow/PHASES.md`（監査観点）
- `.agents/skills/testing/` 配下（generate-scenarios / map-coverage）
- 既存遵守例:
  - Shell: `scripts/test/monitor_test.sh` / `scripts/test/version_stamp_test.sh`
  - Swift pure-core: `Sources/MacHealthCheck/main.swift`
  - Swift XCTest: `Tests/MacHealthKitTests/MenuModelTests.swift`

### 1.1 確認した README

- `scripts/test/README.md` — **未配置**（要確認）。既存 shell テスト 5 本（monitor_test / metrics_test / log_rotate_test / install_metrics_smoke_test / version_stamp_test）の冒頭ヘッダコメント方式が事実上の規約。
- `Tests/README.md` / `Tests/MacHealthKitTests/README.md` — **未配置**。既存 XCTest 9 本の冒頭 doc comment + 各 method の `///` シナリオが規約。
- `Sources/MacHealthCheck/README.md` — **未配置**。`main.swift` 冒頭の `// 形式は .agents/TEST_BDD_FORMAT.md に従う` が規約。`useCase("…") { scenario("…") { … } }` の DSL で書く。

→ README が無いため、本 issue では **既存遵守例をそのまま踏襲**することで規約遵守とする（判断根拠を本 memo に明記）。

## 2. 遵守事項チェックリスト（着手前確認）

| 項目 | 規約 | 適用方針 |
|---|---|---|
| ファイル先頭 | `# Mac Health Keeper - <対象> の単体テスト` + 1〜3 文の目的 | 新規 shell テストでも踏襲 |
| BDD レイヤー | ユースケース / シナリオ / Given/When/Then | 全テストファイルに必須 |
| ユースケース | doc コメント（shell ならファイル冒頭の `# ユースケース:`、Swift なら useCase() ブロック）で**まとまり単位**に 1 〜 3 文 | 必須 |
| シナリオ | **各テストケースの直前**に `# シナリオ:` または scenario() で 1〜3 文 | 必須 |
| Given/When/Then | **各ブロックの直上にコメント 1 つ**。コメントだけ先にまとめるのは禁止 | 必須 |
| And | 2 段目以降の Given / 複数 Then / 追加 When に `And (Given/Then/When):` | 必要に応じて |
| 01・03 対応 | コメント内に「01 UC1-S1」等の対応付け可 | 推奨 |
| 集計 | `$PASS passed, $FAIL failed` を末尾に出す（shell） | 必須 |
| 副作用 | テストは破壊的副作用なし（tempdir / trap で teardown） | 必須 |

## 3. 00〜03 の追補方針（新規機能追加 posture）

ユーザー指示「リファクタではなく新規機能追加」を受け、本 issue は「ロード失敗の最小パッチ」ではなく「LaunchAgent ライフサイクル管理基盤の新規導入」として再評価する。

### 3.1 追補内容

- **00 §2.2 新規機能要件** に追加項目を入れる:
  - `scripts/lib/launchagent_lifecycle.sh` — bootout → bootstrap → verify を集約する新規モジュール
  - `scripts/lib/plist_validator.sh` — plist 構文検証の新規モジュール
  - `scripts/bin/launchagent-doctor.sh` — 4 件 plist の load 状態診断スクリプト
  - `Sources/MacHealthKit/LaunchAgentStatus.swift` — LaunchAgent 状態の純粋型 + パース
- **01 §2.2** に **UC4: LaunchAgent ライフサイクル管理基盤** を新規 UC として追加し、`load_launchagent` 関数の冪等性・stderr 構造化・verify API の正しさをカバー。**UC5: 診断スクリプト** を追加（doctor の出力契約）。
- **02 §2.3 コンポーネント構成** に新規モジュール 4 件を追加し、責務境界を明確化。
- **03 §2** に新規タスクを追加（タスク 2 plist 構文修正の後に、新タスク「launchagent_lifecycle.sh 新規追加」「plist_validator.sh 新規追加」「launchagent-doctor.sh 新規追加」「LaunchAgentStatus.swift 新規追加」を挟む）。

### 3.2 既存セクションへの追記方針

- 既存内容は**改変しない**。新セクションを追加するか、サブセクション末尾に `### N.M (追補)` の見出しで足す。
- 既存 document_id は維持（書き換え禁止）。

## 4. 着手順序

1. 00〜03 の追補（新セクション追加のみ）
2. `Sources/MacHealthKit/LaunchAgentStatus.swift` 新規追加 + pure-core テスト追加（10+ アサーション）
3. `scripts/lib/launchagent_lifecycle.sh` 新規追加 + shell テスト追加（8+ ケース）
4. `scripts/lib/plist_validator.sh` 新規追加 + shell テスト追加
5. `scripts/bin/launchagent-doctor.sh` 新規追加 + shell テスト追加
6. `install.sh` の LaunchAgent ロードブロックを `launchagent_lifecycle.sh` 呼び出しに置換（最小差分）
7. `Tests/MacHealthKitTests/LaunchAgentStatusTests.swift` 新規追加（XCTest）
8. `make check` 全件緑確認
9. `./install.sh` 実機実行 → launchctl 出力エビデンス記録
10. 04_review + verify-and-close memo + workflow.db
