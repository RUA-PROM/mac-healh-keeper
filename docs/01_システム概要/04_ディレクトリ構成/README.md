---
document_id: "FA5889B1-E719-4781-AD95-61CE8C765EC4"
---

このドキュメントは、Mac Health Keeper のソースツリーと各ディレクトリの役割を定義します。
システム仕様書作成ルールは [`.agents/DOCS_RULES.md`](../../../.agents/DOCS_RULES.md) を参照してください。

> 本ドキュメントは「生きているドキュメント」です。実装変更時（各サブ issue 完了時）に更新し、レビュー結果は [`docs/00_review/`](../../00_review/) に記録します。

# 4. ディレクトリ構成

リポジトリのソースツリーと各ディレクトリの役割を、`.agents/spec/02_ディレクトリ構造方針.md` の「**責務単位**でディレクトリを切る」考え方と対応づけて示します。パスはすべてリポジトリルートからの相対表記です（個人の絶対パスは記載しません）。生成物（`.build` / `.DS_Store` 等）は一覧から除外します。

---

## 4.1. トップレベル構成

### ツリー

```text
mac-health-keeper/
├── src/                       # UI 層（AppKit 依存）
│   ├── MacHealth.swift        #   AppDelegate（調整役）
│   ├── MenuBuilder.swift      #   NSMenu 変換
│   ├── MetricsCollector.swift #   メトリクス収集（Imperative Shell）
│   └── Info.plist             #   アプリの Info.plist
├── Sources/
│   └── MacHealthKit/          # Domain(Functional Core) + Infra(Imperative Shell)・Foundation のみ
│       ├── JobCatalog.swift
│       ├── ScheduleTiming.swift
│       ├── MetricsParser.swift
│       ├── MenuModel.swift
│       ├── Metrics.swift
│       ├── AppleScriptEscaper.swift
│       ├── ShellRunner.swift
│       └── JobController.swift
├── Tests/
│   └── MacHealthKitTests/     # XCTest 単体テスト
├── scripts/
│   ├── bin/                   # 実行スクリプト・CLI（launchd 起動対象）
│   ├── lib/                   # 共通ユーティリティ（log/notify/metrics/lock）
│   ├── config/                # 編集可能な設定値（thresholds.sh）
│   └── test/                  # シェルのテスト（bats / *_test.sh）
├── launchagents/              # launchd ジョブ定義テンプレート（*.plist.template）
├── docs/                      # システム仕様書（本ドキュメント群）
├── .agents/                   # 実行契約・規約（汎用テンプレート）
├── .agents-project/           # プロジェクト固有ルール（.agents より優先）
├── .workflow/                 # ワークフロー成果物（00〜04・issue・workflow.db）
├── Package.swift              # SwiftPM 構成
├── Makefile                   # ビルド・テスト
├── install.sh / uninstall.sh  # 配布 / 撤去
├── README.md / LICENSE        # プロジェクト README・ライセンス
└── AGENTS.md / CLAUDE.md      # エージェント向け規約の入口
```

### トップレベル役割表（責務単位・spec/02 対応）

| パス | 役割（責務単位） |
| ---- | ---------------- |
| `src/` | UI 層（AppKit 依存）。`AppDelegate`（`MacHealth.swift`）・`MenuBuilder`・`MetricsCollector`・`Info.plist`。 |
| `Sources/MacHealthKit/` | Domain（Functional Core）＋ Infra（Imperative Shell）。Foundation のみ依存。テスト対象。 |
| `Tests/MacHealthKitTests/` | XCTest 単体テスト（Core / Infra の純粋・契約テスト）。 |
| `scripts/bin/` | 実行スクリプト（monitor / docker / uptime / refresh）と CLI `mac-health`。launchd 起動対象。 |
| `scripts/lib/` | 共通ユーティリティ（log・notify・metrics・lock）。Functional Core / Imperative Shell。 |
| `scripts/config/` | 編集可能な設定値（`thresholds.sh`）。 |
| `scripts/test/` | シェルのテスト（bats / `*_test.sh`）。 |
| `launchagents/` | launchd ジョブ定義テンプレート（`*.plist.template`）。 |
| `docs/` | システム仕様書（本 issue の成果物）。 |
| `.agents/` | 実行契約・規約（汎用テンプレート）。 |
| `.agents-project/` | プロジェクト固有ルール（`.agents` より優先）。 |
| `.workflow/` | ワークフロー成果物（00〜04・issue・workflow.db）。 |
| ルート（`Package.swift` / `Makefile` / `install.sh` / `uninstall.sh`） | SwiftPM 構成・ビルド・配布 / 撤去。 |

---

## 4.2. Swift（`src` / `Sources/MacHealthKit` / `Tests`）

| パス | 役割 |
| ---- | ---- |
| `src/MacHealth.swift` | `AppDelegate`。メニューバー UI とユーザー操作の調整役。各層へ委譲する。 |
| `src/MenuBuilder.swift` | `[MenuItemSpec]` を NSMenu / NSMenuItem へ変換する薄い AppKit 部。 |
| `src/MetricsCollector.swift` | 実コマンドを実行し MetricsParser に委譲して MetricsSnapshot を組み立てる（Imperative Shell）。 |
| `src/Info.plist` | アプリの Info.plist（メニューバー常駐アプリ設定）。 |
| `Sources/MacHealthKit/*` | Domain（`JobCatalog`・`ScheduleTiming`・`MetricsParser`・`MenuModel`・`Metrics`・`AppleScriptEscaper`）と Infra（`ShellRunner`・`JobController`）。AppKit 非依存ゆえテスト可能。 |
| `Tests/MacHealthKitTests/*` | MacHealthKit の XCTest 単体テスト（JobCatalog / ScheduleTiming / MetricsParser / MenuModel / JobController / ShellRunner 契約・注入 / AppleScriptEscaper 等）。 |

> **境界の根拠**: UI（AppKit 依存）を `src/`、テスト可能な純粋ロジック＋副作用境界（Foundation のみ）を `Sources/MacHealthKit/` に分離することで、Domain / Infra を AppKit から独立して検証できます（責務単位の分離）。

---

## 4.3. シェル（`scripts/{bin,lib,config,test}`）

| パス | 役割 |
| ---- | ---- |
| `scripts/bin/monitor.sh` | メモリ／負荷監視ジョブ（launchd: monitor）。 |
| `scripts/bin/check-docker.sh` | Docker アイドル監視ジョブ（launchd: docker）。 |
| `scripts/bin/check-uptime.sh` | 長期稼働の通知ジョブ（launchd: uptime）。 |
| `scripts/bin/refresh.sh` | アプリ自動再起動ジョブ（launchd: refresh）。 |
| `scripts/bin/mac-health` | CLI エントリポイント（`run <job>` 等）。 |
| `scripts/bin/notification_cooldown.sh` | 通知クールダウン制御。 |
| `scripts/lib/log.sh` | ログ記録・世代ローテート（`rotate_logs`）。 |
| `scripts/lib/notify.sh` | osascript によるデスクトップ通知。 |
| `scripts/lib/metrics.sh` | メトリクス取得処理の集約。 |
| `scripts/lib/lock.sh` | ローテート等の排他制御（多重実行の競合防止）。 |
| `scripts/config/thresholds.sh` | 閾値・ローテート世代数・クールダウン等の編集可能な設定値。 |
| `scripts/test/*` | シェルのテスト（`*.bats` / `*_test.sh`）。`make test-shell` で実行。 |

---

## 4.4. 配置物・運用（`launchagents` / ルートスクリプト）

| パス | 役割 |
| ---- | ---- |
| `launchagents/com.github.adachi-tatsuru.machealth.<job>.plist.template` | 各ジョブの launchd 定義テンプレート（`{{HOME}}` プレースホルダ）。`<job>` は monitor / docker / uptime / refresh。 |
| `install.sh` | スクリプト・LaunchAgents の配置と登録（`{{HOME}}` を実環境に展開）。 |
| `uninstall.sh` | 配置物の撤去・LaunchAgents の解除。 |
| `Makefile` | ビルド・テスト（Swift / シェル）のエントリポイント。 |
| `Package.swift` | SwiftPM のパッケージ定義（MacHealthKit ターゲット・テストターゲット）。 |

---

## 4.5. ドキュメント・規約（`docs` / `.agents` / `.agents-project` / `.workflow`）

| パス | 役割 |
| ---- | ---- |
| `docs/` | システム仕様書。`00_review/`（レビュー記録）・`01_システム概要/`（概要・アーキテクチャ・ディレクトリ構成）。 |
| `.agents/` | 実行契約・規約・spec・commands・skills（汎用）。 |
| `.agents-project/` | プロジェクト固有ルール（`.agents` より優先）。 |
| `.workflow/` | ワークフロー成果物（issue・00〜04・templates・workflow.db）。 |

---

## 4.6. テストディレクトリのルール（方針）

- **テストピラミッド**: 純粋ロジック（Domain）の単体テストを厚く配置する。
- **配置の一意性**: Swift（MacHealthKit）のテストは `Tests/MacHealthKitTests/`（XCTest）、シェルのテストは `scripts/test/`（bats / `*_test.sh`）に置き、例外を作らない。
- **命名**: Swift は `<対象>Tests.swift`、シェルは `<対象>_test.sh` / `<対象>.bats` で対象が分かるようにする。

---

## 参考資料

- [01 システム概要](../README.md)
- [03 アーキテクチャ](../03_アーキテクチャ/README.md)
- `.agents/spec/02_ディレクトリ構造方針.md`、`.agents/spec/03_命名規則.md`

---

**最終更新**: 2026 年 05 月 28 日
