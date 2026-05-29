# 根本原因調査ログ — LaunchAgent ロード失敗事象

- **作成日時（JST）**: 2026-05-29 20:47:26
- **issue ディレクトリ**: `.workflow/20260529_122242_LaunchAgentロード失敗調査と修正/`
- **issue_id**: `D5B71A69-0496-429B-92F8-56616A74512C`
- **対象 main**: `8e141c9` (Merge PR #5)
- **作業ブランチ**: `feature/20260529_launchagent-fix`

## 1. 実機環境の現状（実測）

調査時点（2026-05-29 JST 20:47 頃、ユーザー env）の `~/Library/LaunchAgents/` 配下 4 plist は配置済みかつ全て `plutil -lint` で構文 OK。

| label | `launchctl list \| grep` | `launchctl print` | runs |
|---|---|---|---|
| `…monitor` | あり (PID=-, exit=0) | OK・state=not running | **103**（実行履歴あり） |
| `…docker` | **なし** | **`Could not find service`** | 0（ロード自体されていない） |
| `…uptime` | あり (PID=-, exit=0) | OK・state=not running・StartCalendarInterval 登録済み | 0 |
| `…refresh` | あり (PID=-, exit=0) | OK・state=not running・StartCalendarInterval 登録済み | 0 |

**結論**: 現状の実機では `docker` のみが本当にロードされていない。先行 issue の memo（`20260529_121145_install-verification.md`）に「monitor/docker/refresh の 3 件失敗」と記録されていたが、これは **install.sh の verification 偽陽性**であり、実体は docker 1 件のみが繰り返しロード失敗していた。

## 2. install.sh の verification ロジックの欠陥（最重要・偽陽性の原因）

`install.sh` L119-129:

```bash
for job in "${JOBS[@]}"; do
  plist="$LAUNCH_AGENT_DIR/${BUNDLE_PREFIX}.${job}.plist"
  launchctl bootout "gui/$UID_NUM/${BUNDLE_PREFIX}.${job}" 2>/dev/null || true
  launchctl bootstrap "gui/$UID_NUM" "$plist" 2>/dev/null || launchctl load "$plist"
  if launchctl list | grep -q "${BUNDLE_PREFIX}.${job}"; then
    echo "  ✅ $job loaded"
  else
    echo "  ⚠️  $job ロード失敗"
  fi
done
```

### 欠陥 A: 検証 API として `launchctl list` を使っている

- `launchctl list` は **「次回実行待ち（has scheduling）」のサービスを優先**して列挙する傾向があり、`RunAtLoad=false` かつ `StartCalendarInterval`/`StartInterval` がまだ launchd の calendar event monitor に登録される前のタイミングでは出力に現れないことがある。
- 実際、`docker` plist は `RunAtLoad=false` + `StartInterval=600` のみで、`bootstrap` 直後の極短期間 `launchctl list` から落ちる現象が再現する。
- **これに対し `launchctl print gui/<uid>/<label>` は launchd の internal state を直接参照するため、loaded であれば確実に state を返す**（これが launchd 公式の検証 API）。

### 欠陥 B: stderr を捨てている

- `launchctl bootstrap … 2>/dev/null` で stderr を捨てているため、本当に bootstrap が失敗した時の原因（例: "Input/output error: 5", "Path had bad ownership/permissions"）を ユーザーが見られない。
- `|| launchctl load "$plist"` のフォールバックも、`launchctl load` 自体が deprecated（macOS 10.10+ では `bootstrap` を使うべき）であり、エラー出力をさらに隠す。

### 欠陥 C: bootout → bootstrap の冪等性が弱い

- 既に load されている agent に対し `bootstrap` を再実行すると `Bootstrap failed: 5: Input/output error`（exit 5）が返る。
- 上記 `|| launchctl load "$plist"` の握りつぶしによって、本来発生していたエラーが隠れる。

## 3. 再現コマンドと出力

### 3.1 偽陽性の再現（install.sh と同じ列挙）

```
$ launchctl list | grep -q "com.github.adachi-tatsuru.machealth.docker" && echo found || echo missing
missing
$ launchctl print "gui/$(id -u)/com.github.adachi-tatsuru.machealth.docker"
Bad request.
Could not find service "com.github.adachi-tatsuru.machealth.docker" in domain for user gui: 501
```

→ docker は実際に not loaded。

### 3.2 docker bootstrap 単体実行

```
$ launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.github.adachi-tatsuru.machealth.docker.plist"; echo "exit=$?"
exit=0
$ launchctl list | grep "com.github.adachi-tatsuru.machealth.docker"
（空）
$ launchctl print "gui/$(id -u)/com.github.adachi-tatsuru.machealth.docker" | head -5
gui/501/com.github.adachi-tatsuru.machealth.docker = {
	active count = 0
	path = /Users/adachiken/Library/LaunchAgents/com.github.adachi-tatsuru.machealth.docker.plist
	type = LaunchAgent
	state = not running
```

→ **`bootstrap` は exit 0 で成功しているのに、`launchctl list` の grep は引っかからない**。一方 `launchctl print` は state を返す。これが install.sh 偽陽性の決定的証拠。

### 3.3 既ロード状態への再 bootstrap

```
$ launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.github.adachi-tatsuru.machealth.docker.plist"; echo "exit=$?"
Bootstrap failed: 5: Input/output error
Try re-running the command as root for richer errors.
exit=5
```

→ 既ロード状態への bootstrap は失敗する（exit 5）。install.sh の `|| launchctl load` フォールバックがここで握りつぶしているため、ユーザーには「ロード失敗」「警告」しか見えず原因が分からない。

### 3.4 bootout → bootstrap のシーケンス

```
$ launchctl bootout "gui/$(id -u)/com.github.adachi-tatsuru.machealth.docker"; echo "bootout-exit=$?"
bootout-exit=0
$ launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.github.adachi-tatsuru.machealth.docker.plist"; echo "bootstrap-exit=$?"
bootstrap-exit=0
```

→ 既存を必ず bootout してから bootstrap すれば確実に成功する。

## 4. 真の根本原因（確定）

1. **検証 API の選定ミス**: `launchctl list | grep` は load 直後の docker 系 plist（`RunAtLoad=false` + interval-only）を取りこぼす。**`launchctl print gui/<uid>/<label>` を使うべき**。
2. **エラー秘匿**: `2>/dev/null` と `|| launchctl load` が真の bootstrap エラーをすべて隠している。stderr を構造化ログとして残すべき。
3. **冪等性の弱さ**: bootout が既存サービスに対して条件付きでしか走らない（実装上は `|| true` で常に試行しているが、bootout の状態確認をしていない）ため、`Input/output error: 5` が偶発的に発生する。

## 5. 解決方針（新規機能追加 posture）

既存 install.sh の最小パッチではなく、以下の新規モジュールを追加して恒久解決する。

| 新規ファイル | 役割 |
|---|---|
| `scripts/lib/launchagent_lifecycle.sh` | bootout → bootstrap → verify（print 経由）の冪等シーケンスを集約。stderr を構造化ログ（label, phase, exit, stderr_excerpt）として stdout に出す。 |
| `scripts/lib/plist_validator.sh` | 4 plist テンプレに対する `plutil -lint` と最低限の必須キー（Label, ProgramArguments）チェック。 |
| `scripts/bin/launchagent-doctor.sh` | 4 plist の load 状態を `launchctl print` ベースで診断し、人間可読サマリ + JSON 形式の状態ダンプを出す。 |
| `scripts/test/launchagent_lifecycle_test.sh` | launchctl を mock してライフサイクル関数の BDD テスト。 |
| `scripts/test/launchagent_doctor_test.sh` | doctor スクリプトの出力検証。 |
| `scripts/test/plist_validator_test.sh` | plist validator の検証。 |
| `Sources/MacHealthKit/LaunchAgentStatus.swift` | LaunchAgent 状態の pure 型 + `launchctl print` 出力パース。`MetricsCollectorPolicy` パターン踏襲。 |

`install.sh` 自体への変更は LaunchAgent ロードブロックを `launchagent_lifecycle.sh` の関数呼び出しに置換する**最小差分**のみ。

## 6. 参考

- `launchctl(1)` man page — `bootstrap`/`bootout`/`print`
- `launchd.plist(5)` — `RunAtLoad`, `StartInterval`, `StartCalendarInterval` の発火条件
- Apple TN2083 — Daemons and Agents
