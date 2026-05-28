---
document_id: "BED84E31-A870-4105-B363-828E9BAE706C"
---

このドキュメントは、Mac Health Keeper の機能設計（各機能の処理フロー・関係モジュール・既知の制約）のインデックスを定義します。
システム仕様書作成ルールは [`.agents/DOCS_RULES.md`](../../.agents/DOCS_RULES.md) を参照してください。
Mermaid 図作成時は [`.workflow/templates/AGENTS_MERMAID_RULES.md`](../../.workflow/templates/AGENTS_MERMAID_RULES.md) を参照してください。

> 本ドキュメントは「生きているドキュメント」です。実装変更時に更新し、レビュー結果は [`docs/00_review/`](../00_review/) に記録します。

# 4. 機能設計

機能ごとに `docs/04_機能設計/<機能名>/README.md` を作成します。各 README には次の項目を含めます：概要 / 入出力 / 処理フロー（Mermaid sequence または flowchart）/ 関係モジュール / 関連テスト / 既知の制約。

## 4.1. 機能一覧

| 機能 ID | 機能名 | 概要 | ディレクトリ |
| ------- | ------ | ---- | ------------ |
| F001 | メニューバー表示 | ステータスアイコン・NSMenu の構築と再描画 | [メニューバー表示](./メニューバー表示/README.md) |
| F002 | メトリクス収集 | `metrics.sh` 引数呼び出し + 固定文字列残置 3 箇所 + `MetricsParser` | [メトリクス収集](./メトリクス収集/README.md) |
| F003 | ジョブ ON/OFF（CQRS） | `JobController` の load/unload/toggle/enableAll/disableAll と `isLoaded` query | [ジョブON_OFF](./ジョブON_OFF/README.md) |
| F004 | クイック対処 | App Refresh / sudo purge / memory_pressure / Docker Quit | [クイック対処](./クイック対処/README.md) |
| F005 | 監視ジョブ（4 種） | monitor / docker / uptime / refresh の launchd 駆動バッチ | [監視ジョブ](./監視ジョブ/README.md) |
| F006 | 通知（注入耐性付き） | osascript argv 渡し + cooldown 制御 | [通知](./通知/README.md) |
| F007 | ログ・ローテーション | log / log_event / rotate_logs / finalize_job + lock.sh | [ログとローテーション](./ログとローテーション/README.md) |
| F008 | LaunchAgent 配備 | install.sh / uninstall.sh による配置・登録 | [LaunchAgent配備](./LaunchAgent配備/README.md) |

## 4.2. バッチ処理仕様（launchd 駆動の 4 ジョブ）

[監視ジョブ](./監視ジョブ/README.md) に集約しています。スケジュールは [03 データ設計 §3.4](../03_データ設計/README.md#34-launchd-plist-スキーマ) と [01 システム概要 / 03 アーキテクチャ §3.4](../01_システム概要/03_アーキテクチャ/README.md#34-ジョブ一覧) を参照。

---

## 参考資料

- [01 システム概要](../01_システム概要/README.md)
- [02 画面設計](../02_画面設計/README.md)
- [03 データ設計](../03_データ設計/README.md)
- [05 エラー処理と外部通知](../05_エラー処理と外部通知/README.md)
- [99 ID 命名規則と管理](../99_ID命名規則と管理/README.md)

---

**最終更新**: 2026 年 05 月 28 日 / **maintainer**: docs worker
