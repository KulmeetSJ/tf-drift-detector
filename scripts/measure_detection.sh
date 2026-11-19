#!/usr/bin/env bash
# Measures, per drift scenario, the full loop a human would see:
#   induce (gcloud/bq)  ->  drift run (manual dispatch)  ->  issue OPENED
#   restore (terraform apply)  ->  next drift run  ->  issue CLOSED
#
#   scripts/measure_detection.sh [scenario...]      (default: all 7)
#
# Appends rows to measurements/detection.csv. Run from a laptop logged in with gcloud and gh.
# Manual dispatch measures the pipeline itself; with the 6 h schedule, add up to 6 h of waiting
# (3 h on average) plus GitHub's own schedule delay.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
CSV=measurements/detection.csv
SCENARIOS=("$@"); [[ ${#SCENARIOS[@]} -gt 0 ]] || read -r -a SCENARIOS <<<"$(scripts/induce_drift.sh list | awk '{print $1}' | tr '\n' ' ')"

epoch() { date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$1" +%s 2>/dev/null || date -u -d "$1" +%s; }
log()   { echo "[$(date -u +%T)] $*" >&2; }

dispatch_and_wait() {  # prints the run id once it has finished successfully
  local before id=""; before=$(gh run list -w drift -L 1 --json databaseId -q '.[0].databaseId // 0')
  gh workflow run drift.yml >/dev/null
  while [[ -z "$id" || "$id" == "$before" ]]; do sleep 3; id=$(gh run list -w drift -L 1 --json databaseId -q '.[0].databaseId'); done
  gh run watch "$id" --exit-status >/dev/null 2>&1 || { log "drift run $id failed"; exit 1; }
  echo "$id"
}

restore() {
  scripts/induce_drift.sh revert >/dev/null
  GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token) \
    terraform -chdir=infra apply -auto-approve -input=false -no-color >/dev/null
}

[[ -z "$(gh issue list --label drift --state open --json number -q '.[].number')" ]] \
  || { log "a drift issue is already open; close it first"; exit 1; }
[[ -f "$CSV" ]] || echo "scenario,induced_utc,detect_run,issue,opened_utc,detect_s,restored_utc,close_run,closed_utc,close_s,status_reported" >"$CSV"

for s in "${SCENARIOS[@]}"; do
  log "=== $s ==="
  T_IND=$(scripts/induce_drift.sh "$s" | sed -E 's/^\[([^]]+)\].*/\1/')
  RUN1=$(dispatch_and_wait)
  read -r ISSUE OPENED TITLE <<<"$(gh issue list --label drift --state open --json number,createdAt,title -q '.[0] | "\(.number) \(.createdAt) \(.title)"')"
  [[ -n "${ISSUE:-}" ]] || { log "no issue opened for $s"; echo "$s,$T_IND,$RUN1,,,,,,,,MISSED" >>"$CSV"; restore; continue; }
  log "issue #$ISSUE opened $(( $(epoch "$OPENED") - $(epoch "$T_IND") ))s after inducing"

  restore; T_RES=$(date -u +%FT%TZ)
  RUN2=$(dispatch_and_wait)
  CLOSED=$(gh issue view "$ISSUE" --json closedAt -q '.closedAt // empty')
  [[ -n "$CLOSED" ]] || { log "issue #$ISSUE was not closed"; exit 1; }
  log "issue #$ISSUE closed $(( $(epoch "$CLOSED") - $(epoch "$T_RES") ))s after restoring"

  echo "$s,$T_IND,$RUN1,$ISSUE,$OPENED,$(( $(epoch "$OPENED") - $(epoch "$T_IND") )),$T_RES,$RUN2,$CLOSED,$(( $(epoch "$CLOSED") - $(epoch "$T_RES") )),${TITLE#Drift detected: }" >>"$CSV"
done
log "done; rows in $CSV"
