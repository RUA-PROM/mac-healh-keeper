---
document_id: "8653110D-FD7C-4137-9F6F-2846A5ADA5B1"
---

このドキュメントは、Mac Health Keeper のシステム仕様を定義する納品物です。
システム仕様書作成ルールは [`.agents/DOCS_RULES.md`](../.agents/DOCS_RULES.md) を参照してください。

# システム仕様書

Mac Health Keeper は、macOS のメニューバー常駐アプリ（Swift / AppKit）と、launchd 駆動のシェルジョブ（メモリ／負荷監視・Docker アイドル監視・長期稼働通知・アプリ自動再起動）から構成される、ローカル動作の健康監視ツールです。本仕様書はそのアーキテクチャとディレクトリ構成を記述します。

> **このドキュメントは「生きているドキュメント」です。**
> 実装が変われば docs も更新します。各サブ issue（機能追加・リファクタ等）の完了時に、関連するシステム仕様書の更新要否を確認し、必要に応じて加筆修正してください。仕様書の作成・更新には **issue を立てる必要はありません**。レビュー結果・整合性確認・更新内容は [`docs/00_review/`](./00_review/) に `YYYYMMDD_HHMMSS_review.md` として記録します（[`.agents/DOCS_RULES.md`](../.agents/DOCS_RULES.md)）。

---

## ドキュメント構成

本システム仕様書は、以下のセクションで構成されます。v1.1.0 でフル構成（システム概要 / 画面設計 / データ設計 / 機能設計 / エラー処理と外部通知 / ID 命名規則）まで拡充。v1.2.0 で `make check`・GitHub Actions、v1.3.0 で メトリクス非表示修正の恒久対策（警告バナー・MetricsCollectorPolicy・MacHealthCheck・install smoke・Makefile build/install/reinstall）を反映済み。

1. **[システム概要](./01_システム概要/README.md)** — システムの全体像・構成・コンポーネントの責務・ジョブ一覧。
   - [01 プロジェクト概要](./01_システム概要/01_プロジェクト概要/README.md) — 目的・スコープ・成果物・技術スタック・対応 OS・配布形態・ライセンス
   - [02 ステークホルダー](./01_システム概要/02_ステークホルダー/README.md) — 利用者／運用者／開発者／AI エージェント／外部依存
   - [03 アーキテクチャ](./01_システム概要/03_アーキテクチャ/README.md) — 層構成図・Functional Core / Imperative Shell・CQRS・データフロー（メトリクス／ジョブ／通知）・テスト戦略・ビルド／配備フロー・A〜F の改善経緯
   - [04 ディレクトリ構成](./01_システム概要/04_ディレクトリ構成/README.md) — 詳細ツリー（実物）・ファイル別責務一覧（実装の細部）・配置物の実行時所在
2. **[画面設計](./02_画面設計/README.md)** — メニューバー UI の構造（G001〜G012）・項目・絵文字・keyEquivalent・アラート系
3. **[データ設計](./03_データ設計/README.md)** — 値型（MetricsSnapshot/JobStatus/ScheduleKind/MenuItemSpec/MenuAction/JobCatalog）・ファイル形式・launchd plist スキーマ・設定値・ロックファイル
4. **[機能設計](./04_機能設計/README.md)** — 機能別ディレクトリ（メニューバー表示 / メトリクス収集 / ジョブ ON/OFF / クイック対処 / 監視ジョブ / 通知 / ログとローテーション / LaunchAgent 配備 / ローカル検証 / CI・Release 自動化）
5. **[エラー処理と外部通知](./05_エラー処理と外部通知/README.md)** — エラー分類・処理の流れ・通知レベル指針・運用観測点・チェックリスト
6. **[ID 命名規則と管理](./99_ID命名規則と管理/README.md)** — G/F/S/T プレフィックス・launchd ラベル・cooldown キー・メトリクス関数命名・テストファイル命名

---

## ドキュメントの読み方

### 対象読者

- **開発者 / コントリビューター**: 実装の全体像と各層の責務を理解するため。
- **AI エージェント**: 変更箇所の影響範囲を素早く判断するため。

### 記述ルール

- **Mermaid 図**: システム構成・データフロー・遷移を視覚的に表現する。
- **表**: コンポーネントの責務・ディレクトリの役割・ジョブ一覧を構造化して記述する。
- **Markdown + frontmatter**: 各ドキュメントの先頭 YAML に一意の `document_id`（UUID）を付与する。
- **機密情報を含めない**: 個人の絶対パス・トークン・認証情報は記載しない。ホームディレクトリは `$HOME` / `~`、launchd プレースホルダは `{{HOME}}` 表記とする。

### 更新履歴

| 日付       | バージョン | 更新内容                                                                                                                                                                                                  | 更新者 |
| ---------- | ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------ |
| 2026-05-28 | 1.0.0      | 初版作成（アーキテクチャ＋ディレクトリ構成）                                                                                                                                                              | -      |
| 2026-05-28 | 1.1.0      | フル構成へ拡充。01_プロジェクト概要・02_ステークホルダー、02_画面設計、03_データ設計、04_機能設計（メニューバー表示 / メトリクス収集 / ジョブ ON_OFF / クイック対処 / 監視ジョブ / 通知 / ログとローテーション / LaunchAgent 配備）、05_エラー処理と外部通知、99_ID 命名規則と管理を新規作成。03_アーキテクチャ・04_ディレクトリ構成は実装詳細まで反映して拡充。レビュー結果は `docs/00_review/20260528_112137_review.md` に記録。 | docs worker |
| 2026-05-28 | 1.2.0      | `make check` 導入・GitHub Actions（`check.yml` / `create-release.yaml`）・`scripts/lint/`（shellcheck/shfmt/swift-format/swiftlint/source 循環検出/security-scan）の実装を docs に反映。04_機能設計に F009（ローカル検証）・F010（CI・Release 自動化）を新設、01_システム概要 §3.8.1（ローカル検証と CI/Release 自動化）と 04_ディレクトリ構成（`scripts/lint/`・`.github/workflows/`）、99_ID 命名規則（F009/F010・F009-S1/S2・F010-S1/S2）、01_プロジェクト概要 §1.3 / §1.4、02_ステークホルダー §2.2 を同時更新。レビュー結果は `docs/00_review/20260528_144521_review.md` に記録。 | docs worker |
| 2026-05-29 | 1.3.0      | メトリクス非表示修正（`.workflow/20260529_083530_メトリクス非表示修正/`）の実装を docs に反映。`MetricsSnapshot.collectorErrors`（非破壊フィールド追加）・`MetricsCollectorPolicy`（純粋関数・Functional Core）・`MenuModel.errorBannerSpecs`（メニュー警告バナー G013）・`Sources/MacHealthCheck`（XCTest 非依存ランナー）・`scripts/test/install_metrics_smoke_test.sh`（インストール経路の smoke）・`Makefile` の `build / install / reinstall / test-swift-purecore` ターゲットを 02 画面設計 / 03 データ設計（T01 拡張）/ 04 機能設計（F001 / F002 / F008 / F009）/ 05 エラー処理（metrics.sh 不在・トラブルシュート）/ 99 ID 命名規則（G013）/ 01 システム概要（§3.1 / §3.6.1 / §3.7 / §3.8.1 / 01 プロジェクト概要 / 04 ディレクトリ構成）に反映。非破壊変更（契約変更ルール §非破壊変更：フィールド追加・Optional 追加）のため minor bump。レビュー結果は `docs/00_review/20260529_094618_review.md` に記録。 | docs worker |

---

## 参考資料

### プロジェクトドキュメント

- [`.agents/DOCS_RULES.md`](../.agents/DOCS_RULES.md) — システム仕様書の作成・更新ルール（`docs/00_review/` 運用）
- [`.agents/spec/`](../.agents/spec/) — 設計原則・ディレクトリ構造方針・命名規則

### 外部参考資料

- [Mermaid 公式ドキュメント](https://mermaid.js.org/)
- [Markdown ガイド](https://www.markdownguide.org/)

---

**最終更新**: 2026 年 05 月 29 日
