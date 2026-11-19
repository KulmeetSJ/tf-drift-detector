#!/usr/bin/env bash
# Simulates "someone clicked in the console": changes real resources behind Terraform's back.
#
#   scripts/induce_drift.sh list
#   scripts/induce_drift.sh <scenario>... | all
#   scripts/induce_drift.sh revert        # undo the one change Terraform can't (unmanaged grant), then
#                                         # run `terraform -chdir=infra apply` to restore the rest
#
# Each induced scenario appends "<utc>,<scenario>" to measurements/induced.csv, so the time from
# drift introduced to issue opened can be measured. Uses gcloud/bq with your own login.
set -euo pipefail

P="${PROJECT_ID:-tf-drift-sandbox-ntd6t}"
SA() { echo "$1@$P.iam.gserviceaccount.com"; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CSV="$ROOT/measurements/induced.csv"

desc() {
  case "$1" in
    label)            echo "change a cost-center label on sales_reporting" ;;
    public-dataset)   echo "grant allAuthenticatedUsers READER on sales_raw (restricted data made public)" ;;
    binding-member)   echo "add an extra member to the Terraform-managed roles/bigquery.jobUser binding" ;;
    unmanaged-editor) echo "grant roles/editor to reporting-app (a role Terraform does not manage)" ;;
    sa-description)   echo "edit the description of etl-pipeline" ;;
    sa-disabled)      echo "disable the data-analyst service account" ;;
    role-escalation)  echo "add bigquery.tables.getData to the custom datasetAuditor role" ;;
  esac
}
ORDER=(label public-dataset binding-member unmanaged-editor sa-description sa-disabled role-escalation)

q() { "$@" >/dev/null 2>&1 || { echo "failed: $*" >&2; return 1; }; }

induce() {
  case "$1" in
    label)            q bq --project_id="$P" update --set_label cost-center:cc-9999 "$P:sales_reporting" ;;
    public-dataset)
      local f; f=$(mktemp)
      bq --project_id="$P" show --format=prettyjson "$P:sales_raw" \
        | jq '.access += [{"role":"READER","specialGroup":"allAuthenticatedUsers"}]' >"$f"
      q bq --project_id="$P" update --source "$f" "$P:sales_raw"; rm -f "$f" ;;
    binding-member)   q gcloud projects add-iam-policy-binding "$P" --condition=None \
                        --member="serviceAccount:$(SA tf-drift-ci)" --role=roles/bigquery.jobUser ;;
    unmanaged-editor) q gcloud projects add-iam-policy-binding "$P" --condition=None \
                        --member="serviceAccount:$(SA reporting-app)" --role=roles/editor ;;
    sa-description)   q gcloud iam service-accounts update "$(SA etl-pipeline)" --project "$P" \
                        --description="Temporarily repurposed for a migration (changed by hand)" ;;
    sa-disabled)      q gcloud iam service-accounts disable "$(SA data-analyst)" --project "$P" ;;
    role-escalation)  q gcloud iam roles update datasetAuditor --project "$P" --add-permissions=bigquery.tables.getData ;;
    *) echo "unknown scenario: $1 (try: list)" >&2; exit 1 ;;
  esac
  mkdir -p "$(dirname "$CSV")"; [[ -f "$CSV" ]] || echo "induced_utc,scenario" >"$CSV"
  local t; t=$(date -u +%FT%TZ); echo "$t,$1" >>"$CSV"
  echo "[$t] induced $1: $(desc "$1")"
}

case "${1:-list}" in
  list)   for s in "${ORDER[@]}"; do printf "%-17s %s\n" "$s" "$(desc "$s")"; done ;;
  all)    for s in "${ORDER[@]}"; do induce "$s"; done ;;
  revert) # The only change `terraform apply` cannot undo: a grant on a role Terraform doesn't manage.
          q gcloud projects remove-iam-policy-binding "$P" --condition=None \
            --member="serviceAccount:$(SA reporting-app)" --role=roles/editor || true
          echo "removed unmanaged roles/editor grant; now run: terraform -chdir=infra apply" ;;
  *)      for s in "$@"; do induce "$s"; done ;;
esac
