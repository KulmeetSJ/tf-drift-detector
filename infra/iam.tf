# Workload identities for a synthetic reporting system. Everything here fits in a project with no billing.

resource "google_service_account" "etl" {
  account_id   = "etl-pipeline"
  display_name = "ETL pipeline"
  description  = "Loads synthetic sales data into sales_raw."
}

resource "google_service_account" "reporting" {
  account_id   = "reporting-app"
  display_name = "Reporting app"
  description  = "Reads curated tables in sales_reporting."
}

resource "google_service_account" "analyst" {
  account_id   = "data-analyst"
  display_name = "Analyst workbench"
  description  = "Ad-hoc read access for analysts."
}

resource "google_project_iam_custom_role" "dataset_auditor" {
  role_id     = "datasetAuditor"
  title       = "Dataset Auditor"
  description = "Least-privilege read of dataset metadata, for audit tooling."
  permissions = [
    "bigquery.datasets.get",
    "bigquery.datasets.getIamPolicy",
    "bigquery.tables.list",
  ]
}

# google_project_iam_binding is AUTHORITATIVE for its role: a member added to one of these roles
# outside Terraform shows up as drift. (google_project_iam_member would silently ignore it.)
resource "google_project_iam_binding" "job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  members = [
    google_service_account.etl.member,
    google_service_account.reporting.member,
    google_service_account.analyst.member,
  ]
}

resource "google_project_iam_binding" "dataset_auditor" {
  project = var.project_id
  role    = google_project_iam_custom_role.dataset_auditor.id
  members = [google_service_account.analyst.member]
}
