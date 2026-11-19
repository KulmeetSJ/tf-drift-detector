#!/usr/bin/env bash
# Keeps ONE open GitHub issue (label: drift) in step with the latest drift report:
#   not clean, no open issue -> open one
#   not clean, issue open    -> update its body; comment only if the findings changed
#   clean, issue open        -> comment and close it
#   scripts/sync_issue.sh <out-dir>     (needs GH_TOKEN, GITHUB_REPOSITORY, RUN_URL)
set -euo pipefail
OUT="$1"
STATUS=$(jq -r .status "$OUT/metrics.json")
LABEL=drift
NOW=$(date -u +%FT%TZ)
# Fingerprint = the findings only (no timestamps), so an unchanged drift doesn't produce a new comment.
FP=$(sha256sum "$OUT/report.md" | cut -c1-12)

gh label create "$LABEL" --color D93F0B --description "Infrastructure drift or policy violation" 2>/dev/null || true
ISSUE=$(gh issue list --label "$LABEL" --state open --json number --jq '.[0].number // empty')

body() {
  cat "$OUT/report.md"
  printf '\n---\nLast checked: %s by [this run](%s).\n' "$NOW" "$RUN_URL"
  # shellcheck disable=SC2016  # backticks are Markdown, not command substitution
  printf 'Fix: revert the console change, or bring it into code and `terraform apply`. This issue closes itself on the first clean run.\n'
  printf '<!-- fingerprint: %s -->\n' "$FP"
}

if [[ "$STATUS" != clean ]]; then
  if [[ -z "$ISSUE" ]]; then
    url=$(gh issue create --label "$LABEL" --title "Drift detected: $STATUS" --body "$(body)")
    echo "opened $url"
  else
    old_fp=$(gh issue view "$ISSUE" --json body --jq .body | sed -n 's/.*<!-- fingerprint: \([0-9a-f]*\) -->.*/\1/p')
    gh issue edit "$ISSUE" --title "Drift detected: $STATUS" --body "$(body)" >/dev/null
    if [[ "$old_fp" != "$FP" ]]; then
      gh issue comment "$ISSUE" --body "Findings changed ($NOW, [run]($RUN_URL)). The description has the current report." >/dev/null
      echo "updated #$ISSUE (findings changed)"
    else
      echo "updated #$ISSUE (no change in findings)"
    fi
  fi
elif [[ -n "$ISSUE" ]]; then
  gh issue close "$ISSUE" --comment "Clean as of $NOW ([run]($RUN_URL)): no drift, no policy violations. Closing." >/dev/null
  echo "closed #$ISSUE"
else
  echo "clean, no open issue"
fi
