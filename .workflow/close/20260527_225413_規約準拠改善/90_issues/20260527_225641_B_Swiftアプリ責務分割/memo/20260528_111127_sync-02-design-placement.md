---
document_id: "64262352-9571-4AF3-BF3F-6610D9D4CDC3"
---

# memo: 修正B（指摘 1）02_設計.md の配置記述を実装に同期

**対象 issue**: サブ B Swift アプリの責務分割
**対応する指摘**: 04_review.md §4.3 指摘 1（02_設計 §2.1.1/§2.3/§9.2 と実配置の不整合）
**実行モード**: quick（小修正＋証跡 memo）
**作成日時（JST）**: 2026-05-28 11:11:27（プレフィックスは `TZ=Asia/Tokyo date +%Y%m%d_%H%M%S` 実行で取得）

---

## 1. 背景・問題

02_設計.md は `ShellRunner.swift`・`JobController.swift` を `src/`（AppKit/launchctl 依存層）配置と記載していたが、
実装は両者を `Sources/MacHealthKit/`（Functional Core）に配置している。
これは 03 §2.3.4 注（テスト容易性のため `ShellRunner` protocol と `SpyShellRunner` を `MacHealthKit` に置き `JobController` もそこから参照）
および install.sh の実列挙（L86 ShellRunner.swift / L88 JobController.swift が `$REPO_DIR/Sources/MacHealthKit/` 配下）と整合する妥当な判断（AppKit 非依存でテスト対象化するため）だが、設計書本文（生きたドキュメント）が未同期だった。

## 2. 修正内容（02_設計.md・document_id 不変）

`ShellRunner`/`JobController` の配置記述を `src/` → `Sources/MacHealthKit/` に修正し、理由（AppKit 非依存でテスト対象化するため）を一文添えた。document_id（`824C799F-CD1F-4499-B735-E7E287F15DE5`）は変更していない。他の正しい記述（責務・参照関係・I/F・テスト戦略）は変更なし。

- **§2.1.1 責務一覧表**: `ShellRunner`/`JobController` の「配置」欄を `src/` → `Sources/MacHealthKit/` に修正。各行に AppKit 非依存でテスト対象化する理由を追記。
- **§2.2.2 アーキテクチャ図（mermaid）**: ノード `SR`(ShellRunner)・`JC`(JobController) を `subgraph Shell`（Imperative Shell）から `subgraph Core`（Functional Core / Sources/MacHealthKit）へ移動。
- **§2.3 コンポーネント構成**: `Sources/MacHealthKit/` のリストに `ShellRunner.swift`・`JobController.swift` を追加し、`src/` のリストから削除。末尾の説明文に「`ShellRunner`/`JobController` も AppKit 非依存でテスト容易性のため MacHealthKit に置く（03 §2.3.4 注・install.sh の実列挙と整合）」を追記。
- **§9.2 可用性（install.sh / SwiftPM のファイル列挙）**: `ShellRunner.swift`・`JobController.swift` を `src/` 側列挙から `Sources/MacHealthKit/` 側列挙へ移動。install.sh L80-88 の実列挙と一致させた。

## 3. 整合確認

- `grep` で 02_設計.md 内の `ShellRunner`/`JobController` 配置記述に `src/` 配置の誤記が残っていないことを確認。
- install.sh の実列挙（L80-88）と §9.2 の記述が一致することを確認（`src/`: MacHealth/MetricsCollector/MenuBuilder、`Sources/MacHealthKit/`: ScheduleTiming/Metrics/JobCatalog/MetricsParser/MenuModel/ShellRunner/JobController）。
- 振る舞い・ビルド・テストには影響しないドキュメント同期のみ（コード未変更）。

## 4. 変更ファイル

- `.workflow/20260527_225413_規約準拠改善/90_issues/20260527_225641_B_Swiftアプリ責務分割/02_設計.md`（§2.1.1 / §2.2.2 図 / §2.3 / §9.2。document_id 不変）

## 5. 自己判定

指摘 1 対応完了。document_id 不変を確認。docs↔実装の不整合を解消（spec/06「docs と実装の不整合を放置しない」）。
