# Ruleset `required_approving_review_count` を 0 に調整

- 日時: 2026-05-29 21:57 JST
- 対象 ruleset: id=17028735（"main branch protection"）
- 変更理由: solo dev では PR の self-approve ができず、`required_approving_review_count=1` のままだと自分の PR を絶対に merge できず構造的に詰む。オーナー裁量により `0` に PATCH。
- 維持した安全策:
  - `enforcement: active` を維持
  - `required_status_checks`（`check` job 必須・strict）を維持
  - `non_fast_forward` / `deletion` / `required_linear_history` を維持
  - `dismiss_stale_reviews_on_push: true` を維持（レビューがある場合は新 push で dismiss）
  - `bypass_actors` は `OrganizationAdmin` のみ（追加なし）
- API 経由メモ: `PATCH /repos/{owner}/{repo}/rulesets/{ruleset_id}` は HTTP 404 を返すため、GitHub Rulesets API は **`PUT`** を使うのが正しい（`gh api --method PATCH` も同様に 404）。curl で `PUT` 経由で更新成功。

## 前 (抜粋)

```json
{
  "type": "pull_request",
  "parameters": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews_on_push": true,
    "required_reviewers": [],
    "require_code_owner_review": false,
    "require_last_push_approval": false,
    "required_review_thread_resolution": false,
    "allowed_merge_methods": ["merge", "squash", "rebase"]
  }
}
```

## 後 (抜粋)

```json
{
  "type": "pull_request",
  "parameters": {
    "required_approving_review_count": 0,
    "dismiss_stale_reviews_on_push": true,
    "required_reviewers": [],
    "require_code_owner_review": false,
    "require_last_push_approval": false,
    "required_review_thread_resolution": false,
    "allowed_merge_methods": ["merge", "squash", "rebase"]
  }
}
```

## 検証

- `gh api repos/RUA-PROM/mac-healh-keeper/rulesets/17028735` で `required_approving_review_count: 0` を確認
- `enforcement: active` 確認
- 5 種の rule（pull_request / required_status_checks / non_fast_forward / deletion / required_linear_history）全て保持
- `updated_at: 2026-05-29T21:57:55.593+09:00`

## 影響

- 1 人 dev での self-approve なし運用が可能（PR は CI 緑 + linear history + status check で守る）
- レビューを後で必須化したい場合は `required_approving_review_count` を再度上げるだけで戻せる
