---
document_id: "6FD8D575-BC18-49A2-8398-5D570D0D9E00"
issue_id: "45589C5B-60C7-4871-BA6C-79955E7D4BEB"
---

# レビュー書: サブ E システムドキュメント整備

**プロジェクト名**: サブ E システムドキュメント整備
**作成日**: 2026 年 05 月 28 日
**最終更新**: 2026 年 05 月 28 日

> **重要**: **このドキュメントは常に更新**します。レビューで発見した問題点・改善提案・対応内容があれば即座に更新します。
>
> **用語**: [.agents/CONCEPTS.md §用語規約](../../../../.agents/CONCEPTS.md#用語規約) を参照。
>
> **必須**: 本レビューは [`.agents/REVIEW_RULE.md`](../../../../.agents/REVIEW_RULE.md) を参照して実施。レビュー深度は **standard**（既存実装は変更せず docs を新規整備する中規模・ドキュメント整合監査）。command は verify-and-close（skill chain: generate-scenarios → map-coverage → review-code → review-architecture → write-workflow-log）を step5 まで実行。

---

## 1. レビュー概要

### 1.1 レビュー目的（必須）

実装内容（=作成された `docs/` システム仕様書）の確認・規約準拠（DOCS_RULES）・**docs と実装の整合**を監査し、クローズ可否を判定する。

### 1.2 レビュー対象（必須）

- **実装範囲**: `docs/README.md`・`docs/01_システム概要/README.md`・`docs/01_システム概要/03_アーキテクチャ/README.md`・`docs/01_システム概要/04_ディレクトリ構成/README.md`・`docs/00_review/`（.gitkeep）の作成（アーキテクチャ＋ディレクトリ構成の初版）。実コード・plist・install.sh は変更なし。
- **レビュー期間**: 2026-05-28 ～ 2026-05-28
- **レビュー担当者**: 監査者（auditor / verify-and-close worker）

---

## 2. 実装内容の確認

### 2.1 実装完了タスク（または Issue）

| タスク名 | 実装内容 | 実装日 | 担当者 | ステータス |
| -------- | -------- | ------ | ------ | ---------- |
| T1 `docs/README.md` | 仕様書入口（目次・読み方・更新履歴・生きているドキュメント・00_review 運用） | 2026-05-28 | implement worker | 完了 |
| T2 `docs/01_システム概要/README.md` | 概要ハブ（03/04 への目次・初版範囲注記） | 2026-05-28 | implement worker | 完了 |
| T3 `docs/01_システム概要/03_アーキテクチャ/README.md` | 構成図・責務表・技術スタック・層間連携・CQRS・ジョブ一覧・ログ/通知/設定 | 2026-05-28 | implement worker | 完了 |
| T4 `docs/01_システム概要/04_ディレクトリ構成/README.md` | ツリー＋役割表（spec/02 責務単位対応） | 2026-05-28 | implement worker | 完了 |
| T5 ジョブ一覧整合確認（UC2-S1） | §3.4 を plist / JobCatalog と突き合わせ | 2026-05-28 | 監査（本レビュー） | 完了（全一致） |
| T6 `docs/00_review/` 確保・規約準拠確認 | .gitkeep で確保・document_id 一意・機密除外 | 2026-05-28 | implement worker | 完了 |

### 2.2 実装内容の詳細

#### T3: アーキテクチャ仕様書（最重要）

- **変更ファイル**: `docs/01_システム概要/03_アーキテクチャ/README.md`
- **実装方法**: 02_設計 §2.2〜2.4 の Mermaid 図・責務表・データフローを掲載。Functional Core / Imperative Shell、CQRS（JobController）、ShellRunner 引数配列化、log.sh ローテート＋lock.sh を文章化。§3.4 にジョブ一覧表。
- **確認事項**: 責務表の全コンポーネントが実ファイルに対応するか・A〜F の成果記述が実装と一致するか・ジョブ表が一次情報（plist・JobCatalog）と一致するか → **すべて一致を確認（§3・§9）**。

---

## 3. テスト結果の確認

### 3.1 単体テスト

本 issue の成果物はコードではなく `docs/` の Markdown であり、自動単体テストは存在しない（02 §6・03「単体テスト」節で「自動コードテスト非該当」と明記済み。理由: Markdown の意味的妥当性・実装整合の判断にレビューを要する）。代替として 01 BDD（UC1-S1/UC1-S2/UC2-S1）に対応する **受け入れ確認チェックリスト（○/×）** を監査者が実コマンドで実行した。

#### 受け入れ確認実行結果（必須: 数値で記載）

- **実行日**: 2026-05-28
- **確認シナリオ数**: 3（UC1-S1 / UC1-S2 / UC2-S1）
- **○（合格）**: 3
- **×（不合格）**: 0
- **要修正（軽微・任意）**: 1（後述 §4.2 指摘 1・低）

#### 実行コマンドと結果（証跡）

| シナリオ | 実コマンド（要約） | 結果 |
| -------- | ------------------ | ---- |
| UC1-S1 docs 存在 | 4 docs + `docs/00_review/.gitkeep` の存在確認 | 全て `OK exists`（○） |
| UC1-S2 document_id 一意 | `grep -REho 'document_id: "[^"]+"' docs \| sort \| uniq -d` | 重複 0（NO DUPLICATES・○） |
| UC1-S2 UUID 形式 | 各 docs の frontmatter を 8-4-4-4-12 正規表現で検証 | 4/4 `OK UUID`（○） |
| UC1-S2 機密情報なし | `grep -RnE '/Users/[A-Za-z0-9._-]+' docs` および token/secret 系語句 | 0 件（○） |
| UC2-S1 ジョブ整合 | `launchagents/*.plist.template` の Label/Schedule/RunAtLoad 抽出 → §3.4 表と突合 | 4 ジョブ全一致（○） |
| Mermaid 構文 | fence 総数の偶奇判定（Python） | 全 docs BALANCED（○・arch=3 mermaid blocks） |

### 3.2 統合テスト / 3.3 E2E テスト

該当なし（静的ドキュメント・外部 API なし）。

---

## 4. コードレビュー（=docs レビュー）

### 4.1 コード品質（docs 品質）

- **リント/フォーマット**: Markdown。Mermaid fence 開閉バランス＝全 docs 偶数で BALANCED（問題なし）。
- **型チェック**: 該当なし。

#### レビュー観点

| 観点 | 確認内容 | 結果 | コメント |
| ---- | -------- | ---- | -------- |
| 可読性 | 浅い階層・目次→各節へ 1〜2 リンク・表/図主体で全体像へ到達できる | OK | spec/01 AI フレンドリー設計に適合 |
| 保守性 | 「生きているドキュメント」「00_review 運用」「将来追記」明記。更新時の参照箇所が分かる | OK | リンク切れ防止（02〜99 は非リンク注記） |
| パフォーマンス | 該当なし（静的文書） | OK | — |
| セキュリティ | 個人 absolute パス・トークンなし。`$HOME`/`{{HOME}}` 表記 | OK | grep で 0 件確認 |

### 4.2 指摘事項

#### 指摘 1: ジョブ短名の表記ゆれ（Docker アイドル監視 の空白）

- **重要度**: 低
- **指摘内容**: アーキテクチャ仕様書 §3.4 と概要表記は「Docker アイドル監視」（全角スペースあり）だが、`Sources/MacHealthKit/JobCatalog.swift` の `shortNames["docker"]` は「Dockerアイドル監視」（スペースなし）。意味は同一で事実誤りではないが、一次情報との文字列完全一致ではない。
- **対応状況**: 未対応（任意）
- **対応方法**: docs 側を「Dock（スペースなしに揃える、または「表示名は可読性のため空白を補う」旨を注記。**クローズを妨げない軽微指摘**。
- **evidence_source**: existing_code（`Sources/MacHealthKit/JobCatalog.swift` L24-28）

#### 指摘 2: `monitor`/`docker` の thresholds 依存の図示（参考・低）

- **重要度**: 低（指摘ではなく確認結果）
- **指摘内容**: 構成図で `monitor & docker --> thresholds` としているが、実装上 uptime/refresh も config を参照しうる。ただし図は主要依存の簡略表現であり、責務理解を損なわない。
- **対応状況**: 対応不要（簡略図として妥当）
- **evidence_source**: existing_code（`scripts/config/thresholds.sh` に cooldown/閾値あり）

---

## 5. ドキュメントの確認

### 5.1 ドキュメント更新状況

| ドキュメント | 更新状況 | 確認者 | 確認日 |
| ------------ | -------- | ------ | ------ |
| [`00_要求定義.md`](./00_要求定義.md) | 更新済み（document_id・issue_id 付与） | 監査 | 2026-05-28 |
| [`01_要件定義.md`](./01_要件定義.md) | 更新済み（BDD UC1-S1/S2・UC2-S1） | 監査 | 2026-05-28 |
| [`02_設計.md`](./02_設計.md) | 更新済み（責務表・図・ジョブ表・テスト読替） | 監査 | 2026-05-28 |
| [`03_実装計画.md`](./03_実装計画.md) | 更新済み（T1〜T6・BDD 対応表） | 監査 | 2026-05-28 |

### 5.2 ドキュメントの整合性

- **実装と設計の整合性**: 整合している（責務表・ジョブ表が実ソースと一致。§9 参照）。
- **要件と実装の整合性**: 整合している（01 BDD 3 シナリオが docs に 1 対 1 対応。§ map-coverage 参照）。
- **コメント**: 02/03 の設計図・ジョブ表が、作成された docs にそのまま反映され、かつ一次情報と一致している。

---

## map-coverage: 01 BDD ↔ 03 受け入れ確認 ↔ docs の対応表

| 01 BDD | 内容 | 03 対応タスク | docs での実現 | 監査検証方法 | 結果 |
| ------ | ---- | ------------- | ------------- | ------------ | ---- |
| **UC1-S1** | docs にアーキテクチャ仕様書が存在する | T1/T2/T3/T4 | 4 docs が存在し図/表で関係を示す | `ls` で 4 docs 存在確認・arch に mermaid 3 ブロック | ○ |
| **UC1-S2** | DOCS_RULES の構成・命名・document_id 準拠 | T1〜T4/T6 | 全 docs に一意 UUID・テンプレ構成・機密なし・生きているドキュメント明記 | document_id 重複 0・UUID 形式 4/4・テンプレ階層一致・grep 機密 0 件 | ○ |
| **UC2-S1** | ジョブ一覧が launchagents と一致 | T3（§3.4）/T5（突合） | §3.4 表に 4 ジョブ（ラベル/スケジュール/RunAtLoad/スクリプト） | plist 4 件と JobCatalog を 1 行ずつ突合（§9.1） | ○ |

**カバレッジ**: 01 の全 3 シナリオが 03 受け入れ確認・docs に 1 対 1 対応し、未達なし（全○）。テストコード化できない理由（Markdown の意味的妥当性・実装整合判断にレビューを要する）が 02 §6・03 に明記されており、PHASES「テストコード化の網羅（できない場合は理由明記）」を満たす。

---

## docs 更新

- 要否: **不要**（本 issue 自体が docs 整備であり、その成果物を監査した。追加の docs 更新は本クローズ時点で不要）
- 対象: なし
- 理由: 作成された docs が実装と整合しており、軽微指摘（§4.2 指摘 1）も任意対応のため。なお本監査結果は 04_review に記録した（DOCS_RULES の `docs/00_review/` 運用は将来のレビュー時に活用）。

---

## 9. 設計・境界の確認（review-architecture）

### 9.1 ジョブ整合（UC2-S1・重点）— 一次情報突き合わせ

監査者が `launchagents/*.plist.template`（4 件）を grep して抽出した実値と、`Sources/MacHealthKit/JobCatalog.swift`、docs §3.4 表を 1 行ずつ突合：

| ジョブ | plist Label | plist Schedule | plist RunAtLoad | plist Program | JobCatalog.schedules | docs §3.4 | 判定 |
| ------ | ----------- | -------------- | --------------- | ------------- | -------------------- | --------- | ---- |
| monitor | …machealth.monitor | StartInterval 300 | true | bin/monitor.sh | .interval(300) | 300秒/true/monitor.sh | 一致 |
| docker | …machealth.docker | StartInterval 600 | false | bin/check-docker.sh | .interval(600) | 600秒/false/check-docker.sh | 一致 |
| uptime | …machealth.uptime | StartCalendarInterval Hour=9 Minute=0 | false | bin/check-uptime.sh | .daily(9,0) | Hour9/Minute0/false | 一致 |
| refresh | …machealth.refresh | StartCalendarInterval Hour=3 Minute=0 | false | bin/refresh.sh | .daily(3,0) | Hour3/Minute0/false | 一致 |

- 漏れ・過不足なし（plist 4 件＝docs 4 行＝JobCatalog.jobs 4 件）。ラベル規則 `com.github.adachi-tatsuru.machealth.<job>` は `JobCatalog.label(for:)` と一致。
- 表示用頻度（5分毎/10分毎/毎日9:00/毎日3:00）は plist 実値の人間向け表記であり矛盾しない旨を docs が注記済み（適切）。

### 9.2 実装との整合（最重要・spec/06）

責務表・構成図に記載されたコンポーネントを実ファイルと対照：

- **UI 層（src/）**: MacHealth.swift（AppDelegate）・MenuBuilder.swift・MetricsCollector.swift・Info.plist — 全て実在（一致）。
- **MacHealthKit（Sources/）**: JobCatalog・ScheduleTiming・MetricsParser・MenuModel・Metrics・AppleScriptEscaper・ShellRunner・JobController の 8 ファイル — 全て実在（一致）。
- **A〜F の成果記述**:
  - ShellRunner 引数配列化: `func run(_ executable: String, _ args: [String])`・`ZshShellRunner`（Process 使用）が実在し、doc の「実行ファイル＋引数配列で直接起動・シェル再パース排除」と一致。
  - JobController CQRS: Query=`isLoaded`、Command=`load/unload/toggle/enableAll/disableAll` が実在し、doc の CQRS 記述と一致。
  - log.sh ローテート＋lock.sh: `rotate_logs`・`finalize_job`（log.sh）、mkdir ベースの排他（lock.sh）が実在し、doc の「ローテート＋lock 排他」と一致。
  - metrics.sh 集約: `scripts/lib/metrics.sh` に metrics_* 関数群があり、`monitor.sh` が `source lib/metrics.sh`（「lib/metrics.sh に集約」コメント）。doc の「メトリクス取得処理を集約」と一致。
- **存在しない構造・誤記**: 検出されず。記載パス（src/Sources/Tests/scripts/{bin,lib,config,test}/launchagents/docs/Package.swift/Makefile/install.sh/uninstall.sh）は全て実在。

### 9.3 spec 準拠

- **spec/01 設計原則**: 明確な境界・単一責務・UNIX 哲学（初版を最小本数に限定）・AI フレンドリー設計を docs が反映。
- **spec/02 ディレクトリ構造方針**: 役割表が「責務単位」と対応づけ。docs の格納構造（`01_システム概要/03_アーキテクチャ` 等）が `.workflow/templates/docs/` の階層・命名と一致。
- **spec/03 命名規則**: ディレクトリ・ファイル名がテンプレートと一致（番号プレフィックス・節名整合）。

### 9.4 初版範囲の適切性

- 初版範囲＝アーキテクチャ＋ディレクトリ構成に適切に限定。02〜99（画面/データ/機能/エラー処理/ID 管理）と 01_プロジェクト概要・02_ステークホルダーは「将来追記」と明記し、リンク切れを作らない（00 §7.2 スケジュールリスク対策と整合）。

### 9.5 境界・依存の確認

- **責務の境界**: docs 間は README をハブとする一方向目次＋同階層相互参照のみ。循環なし（02 §2.1.3 と一致）。
- **依存関係**: 記述対象側（UI→Kit→シェル/launchd）の依存方向が構成図・責務表で明確。意図しない依存・循環の記述なし。

### 9.6 重要判断の根拠（evidence_source）

| 判断内容 | evidence_source | 備考（参照元） |
| -------- | --------------- | -------------- |
| ジョブ表が実装と完全一致（UC2-S1 合格） | existing_code | `launchagents/*.plist.template`（4 件）grep 実値・`Sources/MacHealthKit/JobCatalog.swift` L21-49 |
| 責務表の全コンポーネントが実在 | existing_code | `ls src/`・`ls Sources/MacHealthKit/`・`ls scripts/{bin,lib,config,test}` |
| A〜F 成果記述が実装と一致 | existing_code | `ShellRunner.swift` L16/24/30・`JobController.swift` L37-87・`log.sh` L176-200・`lock.sh` L2-5・`metrics.sh`・`monitor.sh` L15-16 |
| document_id 一意・機密情報なし | test_output | `grep`/正規表現の実行結果（§3.1） |
| Mermaid fence 開閉バランス | test_output | fence 偶奇判定（Python）全 docs BALANCED |
| 構成・命名が DOCS_RULES/テンプレ準拠 | external_spec | `.agents/DOCS_RULES.md`・`.workflow/templates/docs/` 階層 |

> inference_only 単独依存の重要判断はなし。すべて existing_code / test_output / external_spec を伴う。

---

## 11. システム仕様書の更新

### 11.1 確認結果

- **実装した内容**: `docs/` システム仕様書初版（アーキテクチャ＋ディレクトリ構成）。
- **整合性確認**: アーキテクチャ・ディレクトリ構成ともに実ソース（src/Sources/scripts/launchagents/JobCatalog）と整合。

### 11.2 更新状況

- 本 issue の成果物そのものが docs 整備のため、追加の docs 更新は不要。更新履歴は `docs/README.md` に `2026-05-28 / 1.0.0 / 初版作成` として記載済み。

---

## 12. レビュー結果

### 12.1 総合評価

- **実装品質（docs 品質）**: 高（テンプレ準拠・浅い階層・図表主体）。
- **テスト品質（受け入れ確認）**: 高（UC1-S1/UC1-S2/UC2-S1 全○、証跡コマンド明記）。
- **ドキュメント品質**: 高（document_id 一意・機密なし・生きているドキュメント運用明記）。
- **実装整合**: 高（責務表・ジョブ表・A〜F 成果が一次情報と完全一致。誤記・陳腐化・虚偽なし）。
- **総合評価**: 合格。

### 12.2 承認状況

- **総合クローズ判定**: **合格（クローズ可）**。差し戻しを要する重大な不整合・誤記はなし。§4.2 指摘 1（短名の空白表記ゆれ・低）は任意対応でクローズを妨げない。
- **承認日**: 2026-05-28
- **承認コメント**: 01 BDD 3 シナリオが 03 受け入れ確認・docs に 1 対 1 対応し全○。DOCS_RULES 準拠（構成・命名・document_id 一意・00_review 運用・機密なし）。最重要の「docs と実装の整合」を一次情報（plist/JobCatalog/実ソース）と突合し全一致を確認。

---

## 13. 参考資料

- [`00_要求定義.md`](./00_要求定義.md) / [`01_要件定義.md`](./01_要件定義.md) / [`02_設計.md`](./02_設計.md) / [`03_実装計画.md`](./03_実装計画.md)
- 一次情報: `launchagents/*.plist.template`、`Sources/MacHealthKit/JobCatalog.swift`、`Sources/MacHealthKit/{ShellRunner,JobController}.swift`、`scripts/lib/{log,lock,metrics}.sh`、`scripts/bin/monitor.sh`
- ルール: `.agents/REVIEW_RULE.md`、`.agents/DOCS_RULES.md`、`.agents/workflow/PHASES.md`、`.agents/spec/`、`.workflow/templates/docs/`

---

## 14. 前のステップ

- **前**: [`03_実装計画.md`](./03_実装計画.md) - 実装計画フェーズ

---

## 15. 次のステップ

- 本 issue はドキュメント整備のため、クローズして完了。外部設定（05）は不要。
