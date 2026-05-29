# memo: memo 配置規約違反の是正記録

- 取得プレフィックス: `20260529_110755`（`.agents/scripts/memo-prefix.sh` を実行して取得した実時刻 JST）
- 対象 issue: `.workflow/20260529_105524_ビルド時バージョン自動stamp/`
- 是正実施者: サブエージェント（是正タスク受領分）

## 1. 違反事実

直前のサブエージェントが本 issue を作成した際、判断根拠 memo を **issue ルート直下** に作成した。

- 誤: `.workflow/20260529_105524_ビルド時バージョン自動stamp/20260529_110159_memo_判断根拠.md`
- 正: `.workflow/20260529_105524_ビルド時バージョン自動stamp/memo/20260529_110159_judgment-rationale.md`

memo はファイル名のタイムスタンププレフィックスのみは規約準拠（`YYYYMMDD_HHMMSS_`）だったが、**配置先ディレクトリ（`memo/` 配下必須）** を満たしておらず、また `memo_` 接頭辞が冗長になっていた。

## 2. 規約参照（違反対象）

- `.agents/skills/agent/run_command.md` §memo 作成時（Constraints）
  - 「**.workflow/{issue}/memo/** に作成すること。ファイル名に **YYYYMMDD_HHMMSS_**（日本標準時）をプレフィックスとして付与すること。」
- `.agents/agents/worker.md` §証跡を残す
  - 「memo 作成時は `.workflow/{issue}/memo/` に YYYYMMDD_HHMMSS_ プレフィックスで作成。」
- `.agents/commands/review-docs.md` §Process 2-iv, §Done (DoD)
  - 「`.workflow/{issue}/memo/` 以下に YYYYMMDD_HHMMSS_ プレフィックス付き memo として記録」
- `CLAUDE.md` / `AGENTS.md` §issue 作成タスク受領時の標準フロー
  - issue 配下の証跡は `memo/` サブディレクトリを介すること（既存 close 済み issue の配置例参照）。
- 既存 close 例: `.workflow/close/20260529_083530_メトリクス非表示修正/memo/{20260529_094618_spec-review.md, ...}` が遵守されている標準形。

## 3. 是正内容

1. `memo/` ディレクトリを issue 配下に作成。
2. 旧ファイルを `memo/` 配下へ移動し、kebab-case 化したファイル名にリネーム:
   - 旧: `20260529_110159_memo_判断根拠.md`
   - 新: `memo/20260529_110159_judgment-rationale.md`
   - **プレフィックスタイムスタンプ `20260529_110159` は保持**（規約「プレフィックスは作成時刻のみ。後付け変更不可」を踏まえ、再取得しない）。
3. 00/01/02/03 ドキュメント側に旧 memo パスへの相対参照が無いことを `grep` で確認（参照ゼロのため追従修正なし）。
4. 本是正 memo を `memo/` 配下に新規作成。プレフィックスは `.agents/scripts/memo-prefix.sh` の標準出力（`20260529_110755`）から取得。

## 4. 再発防止策（次回サブエージェントへの引き継ぎ）

- **memo は必ず `.workflow/{issue}/memo/` 配下に作成する**。issue ルート直下に置かない。
- ファイル名は `<YYYYMMDD_HHMMSS>_<kebab-name>.md`。`memo_` のような冗長な接頭辞を入れない。
- プレフィックスは memo を作成する都度、`.agents/scripts/memo-prefix.sh` または `TZ=Asia/Tokyo date +%Y%m%d_%H%M%S` を**実行直前に**呼び出して取得する（推測・キャッシュ・固定値禁止）。
- 既存 close 例（`.workflow/close/20260529_083530_メトリクス非表示修正/memo/`）を必ず参照テンプレートとして読むこと。
- issue 作成完了報告前に、`ls .workflow/<issue>/` で「`memo/` がディレクトリとして存在し、issue ルート直下に `*_memo_*.md` 等の散在ファイルが無い」ことをセルフチェックする。

## 5. 残課題

- なし（本 issue は実装フェーズ未着手のため、後続 implement-feature 開始時に本 memo を引き継ぎ参照する）。
