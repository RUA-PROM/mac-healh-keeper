---
document_id: "0AA9723A-84F5-47B7-9766-D61591B4BEF9"
---

このドキュメントは、launchd 駆動の 4 監視ジョブの設計を定義します。

# 監視ジョブ機能（F005 / 4 ジョブ）

## 概要

launchd が指定スケジュールで起動するバッチジョブ群。各ジョブは `trap finalize_job $JOB EXIT` で **共通終了処理（ローテート）** を確実に呼ぶ（02 §3.3）。

| ジョブ | 短名 | スクリプト | 周期 |
| ------ | ---- | ---------- | ---- |
| `monitor` | メモリ／負荷監視 | `scripts/bin/monitor.sh` | 5 分毎（`StartInterval=300`、`RunAtLoad=true`） |
| `docker` | Docker アイドル監視 | `scripts/bin/check-docker.sh` | 10 分毎（`StartInterval=600`） |
| `uptime` | 長期稼働の通知 | `scripts/bin/check-uptime.sh` | 毎日 9:00（`StartCalendarInterval Hour=9 Minute=0`） |
| `refresh` | アプリ自動再起動 | `scripts/bin/refresh.sh` | 毎日 3:00（`StartCalendarInterval Hour=3 Minute=0`） |

---

## F005-1. monitor.sh（PressureWatch）

### 入出力 / 処理フロー

```mermaid
flowchart TD
    Start([launchd 起動]) --> Trap["trap finalize_job EXIT"]
    Trap --> Get["metrics_swap_used_mb / metrics_compressed_gb / metrics_load_1m / metrics_memory_free_pct"]
    Get --> Class["classify_pressure (free_pct → critical/warn/normal)"]
    Class --> Log["log monitor 'swap=… compressed=… load1m=… cores=… pressure=…'"]
    Log --> S1{exceeds_threshold swap_used_mb $THRESHOLD_SWAP_USED_MB}
    S1 -->|Yes| SC1["should_notify swap → notify + log_event WARN"]
    S1 -->|No| C1
    SC1 --> C1{exceeds_threshold compressed_int $THRESHOLD_COMPRESSED_GB}
    C1 -->|Yes| SC2["should_notify compressed → notify + log_event WARN"]
    C1 -->|No| L1
    SC2 --> L1{exceeds_threshold load_int (cores × THRESHOLD_LOAD_AVG_MULTIPLIER)}
    L1 -->|Yes| SC3["should_notify load → notify + log_event WARN"]
    L1 -->|No| P1
    SC3 --> P1{pressure == critical}
    P1 -->|Yes| SC4["should_notify pressure → notify + log_event WARN"]
    P1 -->|No| End
    SC4 --> End([exit 0 + finalize_job])
```

### 4 つの判定

| 判定 | 条件 | 通知 | log_event |
| ---- | ---- | ---- | --------- |
| swap | `swap_used_mb >= THRESHOLD_SWAP_USED_MB`（既定 5000 MB） | `⚠️ Mac Health: スワップ蓄積` | `WARN swap usage XMB exceeded threshold YMB` |
| compressed | `compressed_int >= THRESHOLD_COMPRESSED_GB`（既定 10 GB） | `⚠️ Mac Health: 圧縮メモリ` | `WARN compressed memory XGB exceeded threshold YGB` |
| load | `load_int >= cores × THRESHOLD_LOAD_AVG_MULTIPLIER`（既定 ×10） | `⚠️ Mac Health: 高負荷` | `WARN load avg X exceeded threshold Y` |
| pressure | `classify_pressure(free_pct) == "critical"`（`< 10%`） | `🔥 Mac Health: メモリ圧迫 Critical` | `WARN memory pressure critical` |

各通知は `should_notify <key>` を経由し、`NOTIFICATION_COOLDOWN_MIN`（既定 60 分）以内は再通知しない。

### COOLDOWN_FILE

- ファイル: `$LOG_DIR/.monitor-cooldown`
- 書式: 行ごとに `key:epoch`（[03 データ設計 §3.3.6](../../03_データ設計/README.md#336-t11-cooldown_file通知クールダウン)）
- 更新は `with_lock notify-cooldown` で直列化。

---

## F005-2. check-docker.sh（DockerIdleStop）

### 処理フロー

```mermaid
flowchart TD
    Start([launchd 起動]) --> Trap["trap finalize_job EXIT"]
    Trap --> Q1{Docker Desktop 起動中？<br/>pgrep -f 'Docker Desktop.app/.../Docker Desktop'<br/>または 'com.apple.Virtualization.VirtualMachine'}
    Q1 -->|No| Clean["rm -f $STATE_FILE; log 'Docker not running'; exit 0"]
    Q1 -->|Yes| CC["docker ps -q | wc -l (3秒タイムアウト)"]
    CC --> Q2{container_count != "0"？}
    Q2 -->|Yes| Clean2["rm -f $STATE_FILE; exit 0"]
    Q2 -->|No| State["$STATE_FILE があれば since、無ければ now を書き込み"]
    State --> Calc["elapsed_min = (now - since) / 60"]
    Calc --> Q3{elapsed_min < DOCKER_IDLE_GRACE_MINUTES？<br/>(既定 30 分)}
    Q3 -->|Yes| Skip["exit 0"]
    Q3 -->|No| Q4{is_business_hours?<br/>(08-21 時)}
    Q4 -->|No (業務時間外)| Quit["osascript quit Docker Desktop<br/>notify '🧹 ...自動 Quit'<br/>log_event ACTION<br/>rm -f $STATE_FILE"]
    Q4 -->|Yes (業務時間内)| Cool["$COOLDOWN_FILE 経過確認 (>= 21600s)"]
    Cool -->|経過| Notify["notify '💡 Docker アイドル'<br/>echo now > $COOLDOWN_FILE<br/>log_event INFO"]
    Cool -->|未経過| Skip2["exit 0"]
```

### 特記事項

- 業務時間: `is_business_hours`（`notify.sh`）。`hour ∈ [8, 22)` で `true`。
- 業務時間内通知の cooldown は 6 時間（21600 秒）でハードコード。
- `STATE_FILE=$LOG_DIR/.docker-state` はアイドル開始時刻（epoch）を持つ。

---

## F005-3. check-uptime.sh（UptimeNudge）

### 処理フロー

```mermaid
flowchart LR
    Start([launchd 起動 9:00]) --> Trap["trap finalize_job EXIT"]
    Trap --> Boot["boot_time = sysctl -n kern.boottime | awk '{print $4}' | tr -d ','"]
    Boot --> Calc["elapsed_days = (now - boot_time) / 86400"]
    Calc --> Log["log uptime 'uptime=Ndays'"]
    Log --> Q{elapsed_days >= UPTIME_WARN_DAYS<br/>(既定 30 日)}
    Q -->|Yes| Notify["notify '💡 Mac Health: 長期稼働中'<br/>log_event INFO"]
    Q -->|No| End([exit 0])
    Notify --> End
```

---

## F005-4. refresh.sh（AppRefresh）

### 対象アプリ

順序はメモリリークしやすい順（`APPS` 配列）。

```
Slack → Chatwork → Google Chrome → Firefox → Claude
```

Cursor は **除外**（編集中ファイル保護）。

### 処理フロー

```mermaid
flowchart TD
    Start([launchd 起動 3:00]) --> Trap["trap finalize_job EXIT"]
    Trap --> Log0["log refresh '=== AppRefresh start ==='"]
    Log0 --> Loop[/各 app/]
    Loop --> R{is_running app?<br/>(System Events processes contains app)}
    R -->|No| Skip["log 'not running, skip'"]
    R -->|Yes| Qa["quit_app: osascript with timeout 15s + quit saving no"]
    Qa --> Qr{quit ok?}
    Qr -->|No| LogW1["log_event WARN '$app: quit returned error (likely dirty), skip'<br/>skipped++"]
    Qr -->|Yes| Wait["wait_for_quit: 最大 30 秒"]
    Wait --> Wr{完全に quit？}
    Wr -->|No| LogW2["log_event WARN '$app: did not quit within timeout'<br/>skipped++"]
    Wr -->|Yes| Open["open -a app; sleep 8"]
    Open --> LogA["log_event ACTION '$app: refreshed'<br/>refreshed++"]
    Skip --> Sleep5
    LogW1 --> Sleep5
    LogW2 --> Sleep5
    LogA --> Sleep5["sleep 5"]
    Sleep5 --> Loop
    Loop --> End["log '=== done refreshed=N skipped=M ==='<br/>notify '🌙 AppRefresh 完了'<br/>log_event INFO"]
    End --> Exit([exit 0])
```

### 安全性

- `quit saving no` で「保存しない」を明示。保存ダイアログ等で `osascript` が応答しなければ 15 秒タイムアウトで諦める。
- 完全に quit するまで最大 30 秒 `is_running` を polling。
- 5 秒間隔でアプリ間を逐次処理（バーストを避ける）。

---

## 関係モジュール（共通）

| ファイル | 役割 |
| -------- | ---- |
| `scripts/lib/log.sh` | `log` / `log_event` / `finalize_job`（trap EXIT で必ず呼ぶ）。 |
| `scripts/lib/notify.sh` | `notify` / `is_business_hours`。 |
| `scripts/lib/metrics.sh` | `metrics_*`（monitor が source）。 |
| `scripts/bin/notification_cooldown.sh` | `should_notify` / `exceeds_threshold` / `classify_pressure`（monitor が source）。 |
| `scripts/config/thresholds.sh` | 閾値・cooldown・ローテート設定。 |
| `launchagents/*.plist.template` | スケジュール定義。 |

## 関連テスト

- `scripts/test/monitor.bats` / `monitor_test.sh` — `should_notify` / `classify_pressure` / `exceeds_threshold`。
- `scripts/test/metrics.bats` / `metrics_test.sh` — `metrics_parse_*` / `metrics_uptime_*`。

## 既知の制約

- すべてのジョブは `gui/<uid>` ドメインで動作する。スリープ中は launchd が起動を延期する可能性がある（macOS の電源管理に依存）。
- `refresh.sh` のアプリ起動判定（`is_running`）は `System Events` の `processes` 一覧に依存し、Login 状態でしか動作しない（ログインユーザー以外では `false` を返す可能性）。
- Docker の起動判定は VirtualMachine プロセスまたは `Docker Desktop.app/Contents/MacOS/Docker Desktop` の文字列マッチに依存。
- monitor の cooldown は `key:epoch` 形式で、key の追加時は `should_notify` を呼ぶ箇所と一致させる必要がある。

---

## 参考資料

- [03 アーキテクチャ §3.4 ジョブ一覧](../../01_システム概要/03_アーキテクチャ/README.md#34-ジョブ一覧)
- [03 データ設計 §3.4 launchd plist スキーマ](../../03_データ設計/README.md#34-launchd-plist-スキーマ)
- 一次情報: `scripts/bin/{monitor,check-docker,check-uptime,refresh}.sh`・`launchagents/*.plist.template`

---

**最終更新**: 2026 年 05 月 28 日 / **maintainer**: docs worker
