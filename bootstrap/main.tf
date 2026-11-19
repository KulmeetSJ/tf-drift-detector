# One-time setup, applied from a laptop: lets GitHub Actions in ONE repo read this project
# through Workload Identity Federation. There are no service account keys anywhere.

data "google_project" "this" {}

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github"
  display_name              = "GitHub Actions"
  description               = "OIDC tokens from GitHub Actions"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  display_name                       = "GitHub OIDC"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  # Tokens from any other repository are rejected before any IAM check runs.
  attribute_condition = "assertion.repository == '${var.github_repository}'"
}

resource "google_service_account" "ci" {
  account_id   = "tf-drift-ci"
  display_name = "tf-drift-detector CI (read-only)"
  description  = "Used by GitHub Actions to run terraform plan. Read-only: it can detect drift, never fix it."
}

# Read-only predefined roles: enough to refresh every resource in infra/ and read the live IAM policy.
locals {
  ci_roles = [
    "roles/browser",                           # resourcemanager.projects.get
    "roles/iam.securityReviewer",              # getIamPolicy on the project, SAs, datasets
    "roles/iam.serviceAccountViewer",          # read service accounts
    "roles/iam.roleViewer",                    # read custom roles
    "roles/bigquery.metadataViewer",           # read dataset metadata and access lists
    "roles/serviceusage.serviceUsageConsumer", # charge API quota to this project (user_project_override)
  ]
}

resource "google_project_iam_member" "ci" {
  for_each = toset(local.ci_roles)
  project  = var.project_id
  role     = each.value
  member   = google_service_account.ci.member
}

resource "google_service_account_iam_member" "ci_wif" {
  service_account_id = google_service_account.ci.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}"
}
