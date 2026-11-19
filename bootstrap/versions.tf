terraform {
  required_version = ">= 1.10"

  # Separate state from infra/: the drift-monitored stack must not contain the CI's own identity.
  cloud {
    organization = "kulmeet-sandbox"
    workspaces { name = "tf-drift-bootstrap" }
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.12"
    }
  }
}

provider "google" {
  project = var.project_id

  # Charge API quota to this project, not to the caller's client project. With a gcloud user token
  # the default is gcloud's shared client project, whose per-minute read quota runs out (HTTP 429).
  user_project_override = true
  billing_project       = var.project_id
}
