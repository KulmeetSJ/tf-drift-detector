terraform {
  required_version = ">= 1.10"

  cloud {
    organization = "kulmeet-sandbox"
    workspaces { name = "tf-drift-detector" }
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
