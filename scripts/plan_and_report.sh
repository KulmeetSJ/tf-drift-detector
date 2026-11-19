#!/usr/bin/env bash
# Runs both plans for infra/, the policies, and the report. Used by CI and locally.
#   scripts/plan_and_report.sh <out-dir>
# Writes <out-dir>/{drift.json,plan.json,conftest.json,report.md,metrics.json}.
set -euo pipefail
OUT="$(mkdir -p "$1" && cd "$1" && pwd)"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/infra"

# Exit codes: 0 = no changes, 2 = changes, 1 = error. Only 1 stops the run; drift itself is read
# from the JSON, because a refresh-only plan with a data source exits 2 even when nothing changed.
plan() { local rc=0; terraform plan -input=false -lock=false -no-color -detailed-exitcode "$@" >"$OUT/plan.log" 2>&1 || rc=$?
         [[ $rc -eq 1 ]] && { cat "$OUT/plan.log" >&2; exit 1; }; return 0; }

plan -refresh-only -out="$OUT/drift.tfplan"
terraform show -json "$OUT/drift.tfplan" >"$OUT/drift.json"
plan -out="$OUT/plan.tfplan"
terraform show -json "$OUT/plan.tfplan" >"$OUT/plan.json"
rm -f "$OUT"/*.tfplan "$OUT/plan.log"

conftest test --no-color -o json --policy "$ROOT/policy" "$OUT/plan.json" >"$OUT/conftest.json" || true
python3 "$ROOT/report/report.py" --drift "$OUT/drift.json" --plan "$OUT/plan.json" \
  --policy "$OUT/conftest.json" --out "$OUT/report.md" --metrics "$OUT/metrics.json" >/dev/null
cat "$OUT/metrics.json"
