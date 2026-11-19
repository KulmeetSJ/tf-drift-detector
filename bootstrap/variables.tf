variable "project_id" {
  description = "Sandbox GCP project (no billing account required)."
  type        = string
  default     = "tf-drift-sandbox-ntd6t"
}

variable "github_repository" {
  description = "Only workflows in this repo can impersonate the CI service account."
  type        = string
  default     = "KulmeetSJ/tf-drift-detector"
}
