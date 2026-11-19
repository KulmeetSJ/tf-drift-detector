# BigQuery sandbox (no billing): tables and partitions expire after 60 days, so state that explicitly
# instead of letting the service default it (which would show as a permanent diff).
locals {
  sandbox_expiration_ms = 60 * 24 * 60 * 60 * 1000
}

resource "google_bigquery_dataset" "raw" {
  dataset_id                      = "sales_raw"
  friendly_name                   = "Sales (raw)"
  description                     = "Synthetic sales events as loaded. Restricted."
  location                        = "US"
  default_table_expiration_ms     = local.sandbox_expiration_ms
  default_partition_expiration_ms = local.sandbox_expiration_ms
  labels                          = merge(var.labels, { data-class = "restricted" })

  # access blocks are AUTHORITATIVE: any grant added in the console (e.g. allAuthenticatedUsers) is drift.
  access {
    role          = "OWNER"
    special_group = "projectOwners"
  }
  access {
    role          = "WRITER"
    user_by_email = google_service_account.etl.email
  }
}

resource "google_bigquery_dataset" "reporting" {
  dataset_id                      = "sales_reporting"
  friendly_name                   = "Sales (reporting)"
  description                     = "Curated, aggregated synthetic sales data."
  location                        = "US"
  default_table_expiration_ms     = local.sandbox_expiration_ms
  default_partition_expiration_ms = local.sandbox_expiration_ms
  labels                          = merge(var.labels, { data-class = "internal" })

  access {
    role          = "OWNER"
    special_group = "projectOwners"
  }
  access {
    role          = "WRITER"
    user_by_email = google_service_account.etl.email
  }
  access {
    role          = "READER"
    user_by_email = google_service_account.reporting.email
  }
  access {
    role          = "READER"
    user_by_email = google_service_account.analyst.email
  }
}
