# Shared helpers. Input is `terraform show -json <plan>`.
# Every policy checks two views of the same project:
#   "planned" - what the code would create or keep (catches problems in a PR, before merge)
#   "live"    - what is actually there now (catches console changes on the scheduled run)
package lib

import rego.v1

resources contains {"view": "planned", "r": r} if {
	some r in input.planned_values.root_module.resources
	r.mode == "managed"
}

resources contains {"view": "live", "r": r} if {
	some r in input.prior_state.values.root_module.resources
	r.mode == "managed"
}

# The whole live project IAM policy (data source output), including roles Terraform does not manage.
live_bindings contains b if {
	some b in input.planned_values.outputs.live_project_bindings.value
}

# Members granted by planned IAM resources: {"view","role","member","address"}.
planned_grants contains {"role": r.values.role, "member": m, "address": r.address} if {
	some x in resources
	x.view == "planned"
	r := x.r
	r.type in {"google_project_iam_binding", "google_project_iam_member"}
	some m in members(r.values)
}

members(v) := v.members if v.members
members(v) := [v.member] if v.member

public_members := {"allUsers", "allAuthenticatedUsers"}
