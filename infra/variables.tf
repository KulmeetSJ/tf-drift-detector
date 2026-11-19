variable "project_id" {
  description = "Sandbox GCP project (no billing account required)."
  type        = string
  default     = "tf-drift-sandbox-ntd6t"
}

variable "labels" {
  description = "Required on every labelable resource (enforced by policy/labels.rego)."
  type        = map(string)
  default = {
    owner       = "platform-team"
    env         = "sandbox"
    cost-center = "cc-0000"
  }
}
