package main

import data.lib
import rego.v1

primitive_roles := {"roles/owner", "roles/editor", "roles/viewer"}

# Basic roles are far too broad. roles/owner is tolerated only for human users (break-glass).
denied_primitive(role, member) if {
	role in {"roles/editor", "roles/viewer"}
}

denied_primitive(role, member) if {
	role == "roles/owner"
	not startswith(member, "user:")
}

deny contains msg if {
	some g in lib.planned_grants
	g.role in primitive_roles
	denied_primitive(g.role, g.member)
	msg := sprintf("[planned] %s grants basic role %s to %s; use a predefined or custom role", [g.address, g.role, g.member])
}

deny contains msg if {
	some b in lib.live_bindings
	b.role in primitive_roles
	some m in b.members
	denied_primitive(b.role, m)
	msg := sprintf("[live] project IAM grants basic role %s to %s (not managed by Terraform); remove it or justify it", [b.role, m])
}

deny contains msg if {
	some g in lib.planned_grants
	g.member in lib.public_members
	msg := sprintf("[planned] %s grants %s to %s; project roles must never be public", [g.address, g.role, g.member])
}

deny contains msg if {
	some b in lib.live_bindings
	some m in b.members
	m in lib.public_members
	msg := sprintf("[live] project IAM grants %s to %s; project roles must never be public", [b.role, m])
}

# Keys are long-lived secrets; workloads use Workload Identity Federation instead.
deny contains msg if {
	some x in lib.resources
	x.view == "planned"
	x.r.type == "google_service_account_key"
	msg := sprintf("[planned] %s creates a service account key; use Workload Identity Federation instead", [x.r.address])
}
