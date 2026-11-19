package main

import rego.v1

# ---- input builders -------------------------------------------------------------------------
plan(planned, live, bindings) := {
	"planned_values": {
		"root_module": {"resources": planned},
		"outputs": {"live_project_bindings": {"value": bindings}},
	},
	"prior_state": {"values": {"root_module": {"resources": live}}},
}

iam_binding(role, members) := {
	"address": "google_project_iam_binding.x", "mode": "managed",
	"type": "google_project_iam_binding", "values": {"role": role, "members": members},
}

good_labels := {"owner": "t", "env": "sandbox", "cost-center": "cc-1", "data-class": "internal"}

dataset(labels, access) := {
	"address": "google_bigquery_dataset.d", "mode": "managed",
	"type": "google_bigquery_dataset", "values": {"labels": labels, "access": access},
}

entry(role, f) := object.union(
	{"role": role, "special_group": "", "iam_member": "", "domain": "", "user_by_email": "", "group_by_email": ""},
	f,
)

sa := "etl@p.iam.gserviceaccount.com"

clean := plan(
	[
		iam_binding("roles/bigquery.jobUser", ["serviceAccount:a@p.iam.gserviceaccount.com"]),
		dataset(good_labels, [entry("OWNER", {"special_group": "projectOwners"}), entry("READER", {"user_by_email": sa})]),
	],
	[],
	[{"role": "roles/owner", "members": ["user:someone@example.com"]}],
)

count_matching(msgs, s) := count([m | some m in msgs; contains(m, s)])

# ---- clean baseline -------------------------------------------------------------------------
test_clean_plan_has_no_violations if {
	count(deny) == 0 with input as clean
}

# ---- IAM ------------------------------------------------------------------------------------
test_planned_editor_denied if {
	count_matching(deny, "[planned] google_project_iam_binding.x grants basic role roles/editor") == 1 with input as plan([iam_binding("roles/editor", ["user:a@example.com"])], [], [])
}

test_planned_owner_for_service_account_denied if {
	count_matching(deny, "basic role roles/owner to serviceAccount:") == 1 with input as plan([iam_binding("roles/owner", ["serviceAccount:x@p.iam.gserviceaccount.com"])], [], [])
}

test_owner_for_human_allowed if {
	count(deny) == 0 with input as plan([], [], [{"role": "roles/owner", "members": ["user:a@example.com"]}])
}

test_live_console_editor_grant_denied if {
	count_matching(deny, "[live] project IAM grants basic role roles/editor to user:intern@example.com") == 1 with input as plan([], [], [{"role": "roles/editor", "members": ["user:intern@example.com"]}])
}

test_live_public_project_role_denied if {
	count_matching(deny, "[live] project IAM grants roles/bigquery.dataViewer to allUsers") == 1 with input as plan([], [], [{"role": "roles/bigquery.dataViewer", "members": ["allUsers"]}])
}

test_planned_public_project_role_denied if {
	count_matching(deny, "grants roles/bigquery.dataViewer to allAuthenticatedUsers") == 1 with input as plan([iam_binding("roles/bigquery.dataViewer", ["allAuthenticatedUsers"])], [], [])
}

test_service_account_key_denied if {
	key := {"address": "google_service_account_key.k", "mode": "managed", "type": "google_service_account_key", "values": {}}
	count_matching(deny, "creates a service account key") == 1 with input as plan([key], [], [])
}

# ---- BigQuery -------------------------------------------------------------------------------
test_live_public_dataset_denied if {
	d := dataset(good_labels, [entry("READER", {"special_group": "allAuthenticatedUsers"})])
	count_matching(deny, "[live] google_bigquery_dataset.d grants READER to a public") == 1 with input as plan([], [d], [])
}

test_planned_domain_wide_dataset_denied if {
	d := dataset(good_labels, [entry("READER", {"domain": "example.com"})])
	count_matching(deny, "[planned] google_bigquery_dataset.d grants READER to a public or domain-wide") == 1 with input as plan([d], [], [])
}

test_invalid_data_class_denied if {
	d := dataset(object.union(good_labels, {"data-class": "secret"}), [])
	count_matching(deny, "needs label data-class") == 1 with input as plan([d], [], [])
}

test_restricted_dataset_human_reader_denied if {
	d := dataset(object.union(good_labels, {"data-class": "restricted"}), [entry("READER", {"user_by_email": "analyst@example.com"})])
	count_matching(deny, "is restricted but grants READER to a non-workload principal") == 1 with input as plan([d], [], [])
}

test_restricted_dataset_workload_reader_allowed if {
	d := dataset(object.union(good_labels, {"data-class": "restricted"}), [entry("READER", {"user_by_email": sa})])
	count(deny) == 0 with input as plan([d], [], [])
}

# ---- labels ---------------------------------------------------------------------------------
test_missing_label_denied_in_both_views if {
	d := dataset(object.remove(good_labels, ["cost-center"]), [])
	count_matching(deny, "is missing required label \"cost-center\"") == 2 with input as plan([d], [d], [])
}

# Regression: in planned values unset fields are null, not "" (caused false "domain-wide" hits).
test_null_fields_in_planned_values_are_not_public if {
	d := dataset(good_labels, [{"role": "OWNER", "special_group": "projectOwners", "domain": null, "iam_member": null, "user_by_email": null}])
	count(deny) == 0 with input as plan([d], [], [])
}
