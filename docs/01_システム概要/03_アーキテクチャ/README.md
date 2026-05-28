---
document_id: "C1D1F4B3-E3D5-48D4-9E02-58420F931954"
---

このドキュメントは、Mac Health Keeper のアーキテクチャ（層構成・技術スタック・層間連携・ジョブ一覧・ログ／通知／設定）を定義します。
システム仕様書作成ルールは [`.agents/DOCS_RULES.md`](../../../.agents/DOCS_RULES.md) を参照してください。

> 本ドキュメントは「生きているドキュメント」です。実装変更時（各サブ issue 完了時）に更新し、レビュー結果は [`docs/00_review/`](../../00_review/) に記録します。

# 3. アーキテクチャ

Mac Health Keeper は、**Functional Core / Imperative Shell** と **明確な層分離（UI / Domain / Infra）**、および **launchd 駆動のバッチジョブ** を組み合わせた構成を採ります。純粋ロジック（Functional Core）を `Sources/MacHealthKit`（Foundation のみ依存）に集約してテスト可能にし、副作用（プロセス実行・launchctl・通知）は Imperative Shell（`MetricsCollector`・`ShellRunner`・`JobController`・シェルジョブ）に閉じ込めています。

---

## 3.1. システム構成図

```mermaid
flowchart TD
    User((ユーザー))

    subgraph UI["UI 層 (src/, AppKit/Cocoa 依存)"]
        AppDelegate["AppDelegate<br/>(MacHealth.swift・調整役)"]
        MenuBuilder["MenuBuilder<br/>(NSMenu 変換)"]
        MetricsCollector["MetricsCollector<br/>(Imperative Shell)"]
    end

    subgraph Kit["MacHealthKit (Sources/, Foundation のみ・テスト対象)"]
        direction TB
        subgraph Domain["Domain / 純粋ロジック (Functional Core)"]
            JobCatalog["JobCatalog"]
            ScheduleTiming["ScheduleTiming"]
            MetricsParser["MetricsParser"]
            MenuModel["MenuModel"]
            Metrics["Metrics / JobStatus"]
            AppleScriptEscaper["AppleScriptEscaper"]
        end
        subgraph Infra["Infra (Imperative Shell)"]
            ShellRunner["ShellRunner<br/>(ZshShellRunner)"]
            JobController["JobController<br/>(CQRS)"]
        end
    end

    subgraph Jobs["シェルジョブ (scripts/bin + lib + config)"]
        monitor["monitor.sh"]
        docker["check-docker.sh"]
        uptime["check-uptime.sh"]
        refresh["refresh.sh"]
        cli["mac-health (CLI)"]
        lib["lib: log.sh / notify.sh / metrics.sh / lock.sh"]
        thresholds["config/thresholds.sh"]
    end

    subgraph launchd["launchd (launchagents/*.plist)"]
        LA["LaunchAgents<br/>monitor/docker/uptime/refresh"]
    end

    Logs[("$HOME/Library/Logs/MacHealth")]

    User -->|"メニュー操作"| AppDelegate
    AppDelegate --> MenuBuilder
    AppDelegate --> MetricsCollector
    AppDelegate --> JobController
    MenuBuilder --> MenuModel
    MetricsCollector --> MetricsParser
    MetricsCollector --> ShellRunner
    JobController --> ShellRunner
    JobController -->|"bootout/bootstrap/list"| launchd
    AppDelegate -->|"run &lt;job&gt;"| cli
    launchd -->|"StartInterval / StartCalendarInterval"| monitor & docker & uptime & refresh
    monitor & docker & uptime & refresh --> lib
    monitor & docker --> thresholds
    lib --> Logs
    MetricsCollector -.->|"読む"| Logs
```

### 構成要素の説明（コンポーネント責務表）

各行の責務は現状実装のファイルヘッダコメントを一次情報とします。

| コンポーネント | 層 | 主な依存 | 責務（1 文） |
| -------------- | -- | -------- | ------------ |
| AppDelegate（`src/MacHealth.swift`） | UI | AppKit | メニューバー UI とユーザー操作の調整役。各層へ委譲し自身はロジックを持たない。 |
| MenuBuilder（`src/MenuBuilder.swift`） | UI | AppKit | `[MenuItemSpec]` を NSMenu / NSMenuItem へ変換する薄い AppKit 部。 |
| MetricsCollector（`src/MetricsCollector.swift`） | UI / Infra | ShellRunner, MetricsParser | 実コマンドを実行し出力を MetricsParser に委譲して MetricsSnapshot を組み立てる（Imperative Shell）。 |
| JobCatalog（`Sources/MacHealthKit/JobCatalog.swift`） | Domain | なし | ジョブ ID・短名・頻度・スケジュール種別・launchd ラベル規則の静的定義。 |
| ScheduleTiming（`Sources/MacHealthKit/ScheduleTiming.swift`） | Domain | なし | 時刻計算・相対時刻表示の純粋ロジック（now を引数化）。 |
| MetricsParser（`Sources/MacHealthKit/MetricsParser.swift`） | Domain | なし | コマンド出力テキスト → メトリクス値の純粋パース（丸め・単位・フォールバック）。 |
| MenuModel（`Sources/MacHealthKit/MenuModel.swift`） | Domain | JobCatalog, ScheduleTiming | Snapshot / JobStatus / Catalog → `[MenuItemSpec]` の純粋データ生成。 |
| Metrics（`Sources/MacHealthKit/Metrics.swift`） | Domain | なし | MetricsSnapshot / JobStatus の純粋値型。 |
| AppleScriptEscaper（`Sources/MacHealthKit/AppleScriptEscaper.swift`） | Domain / Util | なし | 通知文字列を osascript の argv で渡すための純粋関数（注入耐性）。 |
| ShellRunner（`Sources/MacHealthKit/ShellRunner.swift`） | Infra | Foundation(Process) | 実行ファイル＋引数配列で外部コマンドを直接起動（シェル再パース排除）。 |
| JobController（`Sources/MacHealthKit/JobController.swift`） | Infra | ShellRunner, JobCatalog | launchctl による状態変更（Command）と状態取得（Query）を CQRS で分離。 |
| シェルジョブ（`scripts/bin/*`） | Job | lib, config | monitor / docker / uptime / refresh と CLI `mac-health`。launchd から起動される実処理。 |
| シェル lib（`scripts/lib/*`） | Job / Infra | lock.sh | log（ローテート含む）・notify・metrics・lock の共通ユーティリティ。 |
| 設定（`scripts/config/thresholds.sh`） | Config | なし | 閾値・ローテート・クールダウン等の編集可能な設定値。 |
| launchd（`launchagents/*.plist.template`） | Scheduler | — | 各ジョブの起動スケジュール（StartInterval / StartCalendarInterval）を定義。 |

---

## 3.2. 技術スタック

| 技術 | バージョン | 用途 |
| ---- | ---------- | ---- |
| Swift | 5.7+ | アプリ本体・MacHealthKit の実装言語 |
| AppKit / Cocoa | macOS SDK | メニューバー UI（`src/`） |
| Foundation | macOS SDK | MacHealthKit の唯一の依存（Process 等） |
| Swift Package Manager / `swiftc` | - | ビルド（`Package.swift` / `Makefile`） |
| bash | - | シェルジョブ・CLI（`scripts/`） |
| launchd | - | ジョブのスケジュール起動（`launchagents/*.plist.template`） |
| osascript | - | デスクトップ通知の発行（`scripts/lib/notify.sh`） |
| XCTest | - | MacHealthKit の単体テスト（`Tests/MacHealthKitTests/`） |
| bats / `*_test.sh` | - | シェルのテスト（`scripts/test/`） |

---

## 3.3. 層間連携

### 3.3.1. UI 層 → MacHealthKit → シェル / launchd

- **UI 層（`src/`）**: AppKit に依存する薄い層。`AppDelegate` が調整役となり、UI 構築は `MenuBuilder`、メトリクス収集は `MetricsCollector`、ジョブ操作は `JobController` に委譲する。`AppDelegate` 自身は業務ロジックを持たない。
- **MacHealthKit（`Sources/`）**: Foundation のみに依存し、AppKit に依存しない。Domain（Functional Core）の純粋ロジックと Infra（Imperative Shell）の副作用境界を含む。AppKit 非依存ゆえ XCTest で単体テスト可能。
- **シェルジョブ（`scripts/`）**: launchd または CLI `mac-health` から起動される独立した実処理。共通処理は `scripts/lib/`、設定値は `scripts/config/thresholds.sh` に分離する。
- **launchd（`launchagents/`）**: 各ジョブを定義したスケジュールで起動する（§3.4）。

### 3.3.2. Functional Core / Imperative Shell

- **Functional Core（純粋ロジック）**: `JobCatalog` `ScheduleTiming` `MetricsParser` `MenuModel` `Metrics` `AppleScriptEscaper`。入力から出力を決定論的に計算し、副作用を持たない。時刻などの外部依存は引数化する（例: `ScheduleTiming` は `now` を引数で受け取る）。
- **Imperative Shell（副作用境界）**: `MetricsCollector`（コマンド実行）・`ShellRunner`（プロセス起動）・`JobController`（launchctl 実行）・シェルジョブ。外界との入出力を担い、計算は Core に委譲する。

### 3.3.3. CQRS（Command / Query 分離）

`JobController`（`Sources/MacHealthKit/JobController.swift`）は、状態変更と状態取得を分離します。

- **Command（状態変更）**: `load` / `unload` / `toggle` / `enableAll` / `disableAll`（launchctl の bootout / bootstrap）。およびシェル側のジョブ実行（monitor / docker / uptime / refresh）。
- **Query（状態取得）**: `isLoaded`（launchctl list を読むのみ・副作用なし）、`MetricsCollector.collect`（メトリクス取得）。

### 3.3.4. シェル安全化（ShellRunner の引数配列化）

`ShellRunner` は、実行ファイルと引数を **配列** で受け取りプロセスを直接起動します（`ShellRunner.run(executable:args:)`）。文字列を経由したシェルの再パースを排除し、引数注入を防ぎます。通知文字列は `AppleScriptEscaper` で osascript の argv として安全に渡します。

### 3.3.5. データフロー

**(A) UI からのメトリクス更新（Query 中心）**

```mermaid
sequenceDiagram
    participant T as Timer(60s)/手動
    participant AD as AppDelegate
    participant MC as MetricsCollector(Shell)
    participant MP as MetricsParser(Core)
    participant JC as JobController(Query)
    participant MM as MenuModel(Core)

    T->>AD: refreshMetricsAsync
    AD->>MC: collect()
    MC->>MP: parse(コマンド出力)
    MC->>JC: isLoaded(job)
    Note over MC,JC: 副作用なし(Query)
    MP-->>MC: メトリクス値
    JC-->>MC: ジョブ状態
    MC-->>AD: MetricsSnapshot
    AD->>MM: build(snapshot)
    MM-->>AD: [MenuItemSpec]
    AD->>AD: rebuildMenu()
```

**(B) launchd 駆動のジョブ実行（バッチ・「起きた事実」をログに記録）**

```mermaid
sequenceDiagram
    participant L as launchd
    participant J as monitor.sh 等
    participant CFG as thresholds.sh
    participant LIB as lib(notify/log/lock)
    participant LOG as Logs/MacHealth

    L->>J: StartInterval / StartCalendarInterval で起動
    J->>CFG: 閾値読込
    J->>J: メトリクス取得・閾値判定
    alt 閾値超過 (cooldown 経過)
        J->>LIB: notify(通知)
    end
    J->>LIB: log_event(結果)
    J->>LIB: finalize_job → rotate_logs (lock)
    LIB->>LOG: 追記 / 世代ローテート
```

> **イベント駆動の注記**: 本システムはメッセージバスを持たないため、ジョブ完了は `log_event`（events.log）に「起きた事実」として記録する同期処理に留めます（JobFinalized 相当をログに記録し、明示的なイベント発行はしません）。spec/06「単純な同期処理で十分な場合は無理にイベント駆動を導入しない」に従います。

---

## 3.4. ジョブ一覧

launchd が起動する 4 つのジョブを示します。**本表の値は `launchagents/*.plist.template`（`Label` / `ProgramArguments` / `StartInterval` / `StartCalendarInterval` / `RunAtLoad`）および `Sources/MacHealthKit/JobCatalog.swift` を一次情報として一致させています。**

| ジョブ ID | 短名 | スクリプト（`scripts/bin/`） | launchd ラベル | スケジュール（plist 実値） | RunAtLoad |
| --------- | ---- | ---------------------------- | -------------- | -------------------------- | --------- |
| monitor | メモリ／負荷監視 | `monitor.sh` | `com.github.adachi-tatsuru.machealth.monitor` | StartInterval 300 秒（5 分毎） | true |
| docker | Docker アイドル監視 | `check-docker.sh` | `com.github.adachi-tatsuru.machealth.docker` | StartInterval 600 秒（10 分毎） | false |
| uptime | 長期稼働の通知 | `check-uptime.sh` | `com.github.adachi-tatsuru.machealth.uptime` | StartCalendarInterval Hour=9 / Minute=0（毎日 9:00） | false |
| refresh | アプリ自動再起動 | `refresh.sh` | `com.github.adachi-tatsuru.machealth.refresh` | StartCalendarInterval Hour=3 / Minute=0（毎日 3:00） | false |

> **頻度表記の整合**: `JobCatalog.swift` の表示用 `frequencies`（monitor=「5分毎」/ docker=「10分毎」/ uptime=「毎日 9:00」/ refresh=「毎日 3:00」）は、plist の数値（300 / 600 秒）・Calendar（9:00 / 3:00）を人間向けに表記したものであり、矛盾はありません。launchd ラベルは `JobCatalog.label(for:)` の規則 `com.github.adachi-tatsuru.machealth.<job>` と一致します。

---

## 3.5. ログ・通知・設定

| 関心事 | 実装 | 内容 |
| ------ | ---- | ---- |
| ログ | `scripts/lib/log.sh` | `$HOME/Library/Logs/MacHealth` 配下に記録。世代ローテート（`rotate_logs`）を持ち、`scripts/lib/lock.sh` の排他制御で多重実行時の競合を防ぐ。 |
| 通知 | `scripts/lib/notify.sh` | osascript でデスクトップ通知を発行。通知文字列は引数として安全に渡す。クールダウン（`scripts/bin/notification_cooldown.sh`）で短時間の通知重複を抑制。 |
| 設定 | `scripts/config/thresholds.sh` | 閾値・ローテート世代数・クールダウン等の編集可能な設定値。各ジョブが読み込む。 |
| メトリクス | `scripts/lib/metrics.sh` | メトリクス取得処理を集約。各ジョブから共通利用する。 |

ログの保存先・plist の出力先はいずれも `$HOME` / `{{HOME}}` で表記し、個人の絶対パスは記載しません。

---

## 参考資料

- [01 システム概要](../README.md)
- [04 ディレクトリ構成](../04_ディレクトリ構成/README.md)
- 一次情報: `launchagents/*.plist.template`、`Sources/MacHealthKit/JobCatalog.swift`、`src/`、`scripts/`

---

**最終更新**: 2026 年 05 月 28 日
