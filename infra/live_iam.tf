# Read the WHOLE live project IAM policy on every plan. Terraform does not manage most roles
# (e.g. roles/owner), so a console grant of roles/editor would not show up as drift.
# Exposing the live policy in plan.json lets the Rego policies check it anyway.
data "google_project_iam_policy" "live" {
  project = var.project_id
}

output "live_project_bindings" {
  description = "Live project IAM bindings at plan time (checked by policy/iam.rego)."
  value       = jsondecode(data.google_project_iam_policy.live.policy_data).bindings
}
