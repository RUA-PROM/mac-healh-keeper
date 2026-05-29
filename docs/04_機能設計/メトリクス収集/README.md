---
document_id: "85B129C0-1B00-4F30-93A8-318CB0F4CBF8"
---

このドキュメントは、メトリクス収集機能の設計を定義します。

# メトリクス収集機能（F002）

## 概要

- `MetricsCollector`（Imperative Shell）が `metrics.sh <metric>` 引数呼び出しで主要メトリクスを取得し、`MetricsParser`（Functional Core）で純粋に値化する。
- 一部（boot epoch / compressor 生ページ / docker count）は `metrics.sh` の戻り値が算出済みのため、入力書式の互換性確保の観点から `/bin/zsh -l -c <固定文字列>` で残置している。残置文字列は固定リテラルでユーザー入力は流入しない（注入面なし）。
- **v1.3.0**: 収集冒頭で `MetricsCollectorPolicy.decide(exists:path:previouslyWarned:)`（純粋関数・Functional Core）を呼び、`metrics.sh` 不在を検知した場合は `MetricsSnapshot.collectorErrors` に警告を追加し、stderr に初回 1 回だけ警告行を書き出す。配置済みに戻れば次回不在時に再度 1 回警告できるようフラグをリセットする。検知結果は `MenuModel.errorBannerSpecs` 経由で G013 警告バナーとして表示される。

## 入出力

| 項目 | 値 |
| ---- | -- |
| 入力 | なし（タイマー / 操作トリガ） |
| 出力 | `MetricsSnapshot`（[03 データ設計 §3.2.1](../../03_データ設計/README.md#321-t01-metricssnapshotmetricsswift)） |
| 副作用 | `metrics.sh` / `/bin/zsh` の起動（読み取り専用コマンド）、`launchctl list`（`isLoaded` 経由）、ログファイル `modificationDate` 読取 |

## 処理フロー（F002-S1: collect() の主シーケンス）

```mermaid
sequenceDiagram
    participant AD as AppDelegate
    participant MC as MetricsCollector
    participant SR as ShellRunner (ZshShellRunner)
    participant MS as metrics.sh (CLI dispatch)
    participant MP as MetricsParser (Core)
    participant JC as JobController
    participant FM as FileManager

    AD->>MC: collect()
    activate MC

    MC->>FM: fileExists(metricsShPath) (v1.3.0)
    FM-->>MC: Bool
    MC->>MC: MetricsCollectorPolicy.decide(exists:path:previouslyWarned:)
    alt exists == false
        MC-->>MC: collectorErrors += missingScriptCollectorError
        opt previouslyWarned == false
            MC->>MC: fputs(missingScriptStderrLine, stderr)
        end
        MC->>MC: warnedAboutMissingScript = true
    else exists == true
        MC->>MC: warnedAboutMissingScript = false (リセット)
    end

    MC->>SR: run("/bin/bash", [metricsShPath, "load"])
    SR->>MS: bash metrics.sh load
    MS-->>SR: "<load_1m_raw>"
    SR-->>MC: text
    MC->>MP: parseLoadAvg(text) → loadAvg

    MC->>SR: run("/bin/bash", [metricsShPath, "swap"])
    SR-->>MC: "512.00M"
    MC->>MP: parseSwapUsed(text) → swapUsed

    MC->>SR: run("/bin/bash", [metricsShPath, "free"])
    SR-->>MC: "43"
    MC->>MP: parseMemoryFreePct(text) → memoryFreePct

    Note over MC,SR: 残置 3 箇所 (shellFixed / 固定文字列)
    MC->>SR: run("/bin/zsh", ["-l","-c","sysctl -n kern.boottime | awk ..."])
    SR-->>MC: "<boot_epoch>"
    MC->>MP: uptimeDaysHours(bootString, nowEpoch) → (days, hours)

    MC->>SR: run("/bin/zsh", ["-l","-c","vm_stat | awk ..."])
    SR-->>MC: "<pages>"
    MC->>MP: compressedGB(pages) → compressedGB

    MC->>SR: run("/bin/zsh", ["-l","-c","pgrep -f 'com\\.apple\\.Virtualization\\.VirtualMachine' && echo 1 || echo 0"])
    SR-->>MC: "0" or "1"
    opt dockerRunning == "1"
        MC->>SR: run("/bin/zsh", ["-l","-c","(docker ps -q | wc -l) & wait + 3s タイムアウト"])
        SR-->>MC: "<count>"
    end
    MC->>MP: dockerLine(running, count) → dockerLine

    loop 各ジョブ
        MC->>JC: isLoaded(job)
        JC-->>MC: Bool
        MC->>FM: attributesOfItem("<logDir>/<job>.log")
        FM-->>MC: modificationDate
        MC->>MC: schedule に応じ nextRun を算出 (interval=last+sec / daily=nextDailyRun)
    end

    MC-->>AD: MetricsSnapshot (lastUpdated=Date())
    deactivate MC
```

## 関係モジュール

| ファイル | 役割 |
| -------- | ---- |
| `src/MetricsCollector.swift` | 調整役（Imperative Shell）。`metric(_:)` / `shellFixed(_:)` / `collect()`。v1.3.0 で `fileExists`（依存注入）と `warnedAboutMissingScript` フラグを保持し、`collect()` 冒頭で `MetricsCollectorPolicy.decide` を呼ぶ。 |
| `Sources/MacHealthKit/MetricsCollectorPolicy.swift` | v1.3.0 追加・Functional Core。`decide(exists:path:previouslyWarned:) -> Decision` で「追加 collectorErrors」「stderr 行」「次回フラグ」を純粋関数として返す。 |
| `Sources/MacHealthKit/MetricsParser.swift` | 純粋パース（`parseLoadAvg` / `parseSwapUsed` / `parseMemoryFreePct` / `uptimeDaysHours` / `compressedGB` / `dockerLine`）。 |
| `Sources/MacHealthKit/ShellRunner.swift` | 引数配列で起動。シェル再パース排除。 |
| `Sources/MacHealthKit/JobController.swift` | `isLoaded(job:)` を提供（query）。 |
| `Sources/MacHealthKit/ScheduleTiming.swift` | `nextDailyRun(hour:minute:now:calendar:)` で次回実行時刻を算出。 |
| `scripts/lib/metrics.sh` | dispatch CLI（`load`/`swap`/`free`/`compressed`/`uptime_days`/`uptime_hours`/`docker`） + 純粋パース関数群 + 取得ラッパ。 |

## 関連テスト

- `Tests/MacHealthKitTests/MetricsParserTests.swift` — trim・丸め・"%.1f GB"・"—" フォールバック・dockerLine 書式の網羅。
- `Tests/MacHealthKitTests/ScheduleTimingTests.swift` — `nextDailyRun` の境界（当日／翌日繰上げ）・`relativeTimeShort` / `relativeNext`。
- `scripts/test/metrics.bats` / `metrics_test.sh` — `metrics_parse_*` / `metrics_uptime_*` の bats + 自前テスト。
- `Tests/MacHealthKitTests/ShellRunnerContractTests.swift` / `ZshShellRunnerInjectionTests.swift` — 引数配列契約と注入耐性。
- `Sources/MacHealthCheck/TestRunner.swift`（v1.3.0 追加） — `MetricsCollectorPolicy.decide` の 4 分岐（exists / not-exists × previouslyWarned）と `missingScriptCollectorError` / `missingScriptStderrLine` の固定書式を BDD 検証。`MetricsParser.parse*` の `"—"` フォールバックも併せて検証。`swift run MacHealthCheck` で常時実行（XCTest 非搭載環境でも走る）。
- `scripts/test/install_metrics_smoke_test.sh`（v1.3.0 追加） — `scripts/lib/metrics.sh` の物理存在（UC6-S1）、`install.sh` の `cp -R scripts/lib/.` が残っていること（UC6-S2）、一時 HOME へコピー後 `bash metrics.sh load/swap/free` が空文字以外を返すこと（UC6-S3）の smoke 検証。

## 既知の制約

- `metrics.sh` 経由 3 種（load / swap / free）は **既存 sed/awk 出力と完全一致** させるため、整形済みでない「生の抽出値」を返す（`metrics_parse_load_1m_raw` / `metrics_parse_swap_raw` / `metrics_parse_free_pct`）。
- 残置 3 箇所（boot/compressor/docker）は `MetricsParser` が「生の boot 文字列」「生ページ数」「コンテナ数文字列」を要求するため寄せると入力書式が変わる。注入面なし（固定リテラル）のため安全。
- Docker のコンテナ数取得は 3 秒タイムアウト（`docker ps -q & p=$!; (sleep 3; kill -9 $p) & wait $p`）。タイムアウト時は `?` を含む文字列となり `MetricsParser.dockerLine` が `?` に正規化。

---

## 参考資料

- [03 アーキテクチャ §3.3.5](../../01_システム概要/03_アーキテクチャ/README.md#335-データフロー)
- [03 データ設計](../../03_データ設計/README.md)
- 一次情報: `src/MetricsCollector.swift`・`Sources/MacHealthKit/MetricsParser.swift`・`scripts/lib/metrics.sh`

---

**最終更新**: 2026 年 05 月 29 日 / **maintainer**: docs worker
