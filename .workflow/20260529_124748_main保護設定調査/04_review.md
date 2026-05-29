---
document_id: "1b3d5f7a-9c02-4e64-8a16-5d8f1e3a4b60"
issue_id: "1d21b7c5-787c-4b58-a447-d26fdcbb6505"
---

# レビュー: main ブランチ保護 Ruleset の適用

**作成日**: 2026 年 05 月 29 日
**実施者**: Claude Code subagent (Opus 4.7)

---

## 1. 実装内容の確認

### 1.1 実施したこと

| 区分 | 内容 |
| --- | --- |
| 文書 | `.workflow/20260529_124748_main保護設定調査/` 配下に 00/01/02/03 を追加 |
| ブランチ | `feature/20260529_main-protection` を main から作成 |
| commit | `a8adcf7 docs(security): main 保護 Ruleset 適用 issue を起票`（追加 commit でこの 04_review を含める） |
| PR | [#4](https://github.com/RUA-PROM/mac-healh-keeper/pull/4) |
| Ruleset | id=`17028735` を `gh api -X POST repos/RUA-PROM/mac-healh-keeper/rulesets` で適用 |
| 実機検証 | `git push origin main` の拒否を実機で再現確認、CI 緑を確認 |

### 1.2 適用 Ruleset の最終 JSON（GitHub API レスポンス）

```json
{
  "id": 17028735,
  "name": "main branch protection",
  "target": "branch",
  "source_type": "Repository",
  "source": "RUA-PROM/mac-healh-keeper",
  "enforcement": "active",
  "conditions": {
    "ref_name": {"exclude": [], "include": ["~DEFAULT_BRANCH"]}
  },
  "rules": [
    {"type": "pull_request", "parameters": {
      "required_approving_review_count": 0,
      "dismiss_stale_reviews_on_push": true,
      "required_reviewers": [],
      "require_code_owner_review": false,
      "require_last_push_approval": false,
      "required_review_thread_resolution": false,
      "allowed_merge_methods": ["merge", "squash", "rebase"]
    }},
    {"type": "required_status_checks", "parameters": {
      "strict_required_status_checks_policy": true,
      "do_not_enforce_on_create": false,
      "required_status_checks": [{"context": "check"}]
    }},
    {"type": "non_fast_forward"},
    {"type": "deletion"},
    {"type": "required_linear_history"}
  ],
  "bypass_actors": [],
  "current_user_can_bypass": "never"
}
```

参考: `gh api repos/RUA-PROM/mac-healh-keeper/rulesets/17028735`

---

## 2. 受け入れ基準の確認（00 §6 ×実機）

| # | 受け入れ基準 | 検証方法 | 結果 |
| --- | --- | --- | --- |
| 1 | Ruleset が `enforcement: active` で適用 | `gh api .../rulesets` レスポンスで `enforcement: "active"` 確認 | **OK** |
| 2 | 直 push 拒否 | main で空 commit 作成 → `git push origin main` が remote 側で拒否 | **OK**（§3 実機ログ A） |
| 3 | PR 経由必須 | Ruleset の `pull_request` rule が active、API レスポンスで確認 | **OK** |
| 4 | 必須 status check (`check`) | Ruleset の `required_status_checks.required_status_checks[0].context == "check"`、実 PR で `gh pr checks 4` 緑 | **OK**（§3 実機ログ B） |
| 5 | force push 拒否 | Ruleset の `non_fast_forward` rule が active | **OK**（構成確認） |
| 6 | deletion 拒否 | Ruleset の `deletion` rule が active | **OK**（構成確認） |
| 7 | linear history | Ruleset の `required_linear_history` rule が active | **OK**（構成確認） |

---

## 3. 実機検証ログ（`.agents-project/受け入れ基準ルール.md` §3.2 準拠）

### A. 直 push 拒否

**実行コマンド**:
```bash
REPO="/Volumes/ssd-01/NextCloud/Documents/各案件管理/builtfunc/mac-health-keeper"
git -C "$REPO" checkout main
git -C "$REPO" pull --ff-only origin main
git -C "$REPO" commit --allow-empty -m "test: ruleset 動作確認用空 commit"
git -C "$REPO" push origin main
```

**結果（remote 出力）**:
```
remote: error: GH013: Repository rule violations found for refs/heads/main.
remote: Review all repository rules at https://github.com/RUA-PROM/mac-healh-keeper/rules?ref=refs%2Fheads%2Fmain
remote: 
remote: - Changes must be made through a pull request.
remote: 
remote: - Required status check "check" is expected.
remote: 
To https://github.com/RUA-PROM/mac-healh-keeper.git
 ! [remote rejected] main -> main (push declined due to repository rule violations)
error: failed to push some refs to 'https://github.com/RUA-PROM/mac-healh-keeper.git'
```

→ **直 push は GH013 エラーで拒否**、ruleset の 2 件（PR 必須・check 必須）を明示。期待通り。
→ 取り消し: `git reset --soft HEAD~1` で空 commit を削除。reset --hard は使わず、安全に巻き戻し完了。working tree クリーン。

### B. PR 経由は CI 緑かつ merge 可能

**実行コマンド**:
```bash
gh pr checks 4 --repo RUA-PROM/mac-healh-keeper
gh pr view 4 --repo RUA-PROM/mac-healh-keeper --json mergeable,mergeStateStatus,statusCheckRollup
```

**結果**:
```
check	pass	41s	https://github.com/RUA-PROM/mac-healh-keeper/actions/runs/26634633304/job/78491716220
{
  "mergeStateStatus": "CLEAN",
  "mergeable": "MERGEABLE",
  "statusCheckRollup": [{
    "__typename": "CheckRun",
    "completedAt": "2026-05-29T11:28:27Z",
    "conclusion": "SUCCESS",
    "name": "check",
    "status": "COMPLETED",
    "workflowName": "check"
  }]
}
```

→ **PR #4 は CI 緑 / `mergeable: MERGEABLE` / `mergeStateStatus: CLEAN`**。
→ 後続で `gh pr merge 4 --squash --delete-branch`（`--admin` 不使用）で merge 予定。

### C. force push / deletion の API 構成確認

実 push は副作用が大きいため省略。Ruleset の `non_fast_forward` / `deletion` / `required_linear_history` の存在は §1.2 API レスポンスで確認済み。

---

## 4. BDD シナリオとの対応（01 §2）

| UC | シナリオ | 検証 | 結果 |
| --- | --- | --- | --- |
| UC1 | 直 push 拒否 | §3-A 実機ログ。expected error `GH013: Repository rule violations` 含む | **PASS** |
| UC2 | PR 経由 merge | §3-B 実機ログ。`mergeable: MERGEABLE`、approve 0 で squash merge 可 | **PASS**（merge 自体は §5 で実施） |
| UC3 | CI 失敗 PR の merge ブロック | Ruleset `required_status_checks.strict: true` + context `check` 構成確認 | **PASS（構成）** |
| UC4-A | force push 拒否 | Ruleset `non_fast_forward` 構成確認 | **PASS（構成）** |
| UC4-B | main 削除拒否 | Ruleset `deletion` 構成確認 | **PASS（構成）** |
| UC4-C | merge commit 拒否（linear history） | Ruleset `required_linear_history` 構成確認 | **PASS（構成）** |

---

## 5. 設計・境界の確認

- **採用方式**: Repository Ruleset（02 §1 通り）。Classic Branch Protection ではない
- **bypass_actors: `[]`**: ADMIN (`adachi-tatsuru`) を含む誰もバイパス不可。`current_user_can_bypass: "never"` で API レスポンスにも反映
- **緊急時の脱出**: `gh api -X PATCH .../rulesets/17028735 -f enforcement=disabled` で一時 disable（02 §5）
- **CI context 名**: `check`（`.github/workflows/check.yml` の `name:` および `jobs.check` 由来）。`required_status_checks` に渡した値と一致

---

## 6. 残課題・ユーザー判断ポイント

### 6.1 別 issue 候補

- マージ方式の絞り込み（`allow_merge_commit=false` / `allow_rebase_merge=false`）— `required_linear_history` で実質 squash か rebase に制限されるが、repo 設定で UI からも狭めると安全
- `delete_branch_on_merge=true` 化
- commit signature 強制（GPG/SSH 署名）
- CODEOWNERS の導入
- `create-release.yaml` の「PR merge 由来 commit のみ tag する」ガード
- CI ワークフローに複数 jobs 追加時の context 名管理

### 6.2 GUI 目視確認（任意）

- GitHub UI Settings → Rules → Rulesets で `main branch protection` (id=17028735) が active 表示
- Settings → Branches で main の状態（rules 適用済み表示）

### 6.3 既知の留意点

- Ruleset の `allowed_merge_methods` は `["merge", "squash", "rebase"]` の既定値が返るが、`required_linear_history` rule が有効なため実質的に `merge` 方式は弾かれる
- `web_commit_signoff_required: false` のため Web 経由 commit でも sign-off 強制なし（別 issue で扱う）

---

## 7. 完了判定

- 受け入れ基準 1〜7 すべて OK
- 実機検証（A: 直 push 拒否、B: PR merge 可能性）取得済み
- `.agents-project/受け入れ基準ルール.md` §3.2 のエビデンス記録要件を満たす

**本 issue 完了条件達成**。

以上。
