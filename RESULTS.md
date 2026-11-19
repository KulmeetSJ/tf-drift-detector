# Results

All numbers are **personal-project benchmarks** on a sandbox GCP project (no billing account) with GitHub-hosted runners,
measured 2026-11-19. Terraform 1.17.2, google provider 8.12.0, Conftest 0.71.1.
Raw data: [`measurements/detection.csv`](measurements/detection.csv) and [`measurements/induced.csv`](measurements/induced.csv).

## Detection: 7 console-style changes, one at a time
`scripts/measure_detection.sh` runs this loop for each scenario: make the change with `gcloud`/`bq`, dispatch `drift.yml`,
wait for the issue, restore with `terraform apply`, dispatch again, wait for the issue to close. No human acts during a run.

| Scenario | Issue | Change → issue opened | Reported as | Restore → issue closed |
|---|---|---|---|---|
| `label` | [#3](https://github.com/KulmeetSJ/tf-drift-detector/issues/3) | 27s | `drift` | 22s |
| `public-dataset` | [#4](https://github.com/KulmeetSJ/tf-drift-detector/issues/4) | 23s | `drift+violations` | 27s |
| `binding-member` | [#5](https://github.com/KulmeetSJ/tf-drift-detector/issues/5) | 26s | `drift` | 28s |
| `unmanaged-editor` | [#6](https://github.com/KulmeetSJ/tf-drift-detector/issues/6) | 28s | `drift+violations` | 28s |
| `sa-description` | [#7](https://github.com/KulmeetSJ/tf-drift-detector/issues/7) | 23s | `drift` | 24s |
| `sa-disabled` | [#8](https://github.com/KulmeetSJ/tf-drift-detector/issues/8) | 23s | `drift` | 28s |
| `role-escalation` | [#9](https://github.com/KulmeetSJ/tf-drift-detector/issues/9) | 26s | `drift` | 24s |

- **7/7 detected, 7/7 auto-closed.** Each issue names the exact resource and attribute (e.g. `google_service_account.analyst` → `disabled`).
- **Median change → issue opened: 26 s** (23–28 s). **Median restore → issue closed: 27 s** (22–28 s).
- These times are for a manual dispatch, so they measure the pipeline itself: runner start, keyless auth, 2 plans,
  policies, report and issue sync. On the 6-hour schedule, add the wait for the next run: up to 6 h, about 3 h on average,
  plus GitHub's schedule delay.
- 2 of the 7 changes also break a policy, so they are reported as `drift+violations`: the restricted dataset made public, and `roles/editor` granted outside Terraform.
- `unmanaged-editor` changes a role Terraform does **not** manage. A plain `terraform plan` shows nothing for it.
  It is caught because the live project IAM policy is read and diffed on every run.

## All 7 at once
Same 7 changes made together, then one manual run ([issue #1](https://github.com/KulmeetSJ/tf-drift-detector/issues/1)):
6 drifted resources + 1 unmanaged IAM grant + 3 policy violations in one issue, and no false positives.
Restore + the next run closed it.

## Shift-left: policy blocks a PR before merge
[PR #2](https://github.com/KulmeetSJ/tf-drift-detector/pull/2) added `allAuthenticatedUsers` READER to `sales_reporting`
("share with partners"). The `pr-plan` job failed with:

> `[planned] google_bigquery_dataset.reporting grants READER to a public or domain-wide principal`

The report was posted as a PR comment. The PR was closed unmerged, and the change never reached GCP.

## Tests
- Policies: 15 `conftest verify` tests (a good and a bad case per rule, plus 1 regression test).
- `report.py`: 11 unit tests, run on real sanitized plan fixtures (clean + all 7 changes).
- CI also runs `terraform fmt`, `validate` (both stacks) and shellcheck.

## False positives found and fixed during development
| Symptom | Cause | Fix |
|---|---|---|
| Clean project reported as drifted | `plan -refresh-only` exits 2 when the config has a data source | Read drift from plan JSON, not the exit code |
| An untouched IAM binding reported as drifted | Project IAM `etag` changes when any binding changes | Ignore provider-recomputed attributes |
| OWNER/WRITER entries flagged "domain-wide" | Unset fields are `null` in planned values, `""` in state | Type-check before comparing; regression test |
| Plan hung for 10 minutes | HTTP 429: quota charged to gcloud's shared client project | `user_project_override` + `billing_project` |
