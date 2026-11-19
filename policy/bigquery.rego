package main

import data.lib
import rego.v1

datasets contains x if {
	some x in lib.resources
	x.r.type == "google_bigquery_dataset"
}

public_entry(a) if a.special_group == "allAuthenticatedUsers"
public_entry(a) if a.iam_member in lib.public_members

public_entry(a) if {
	# whole-domain grants are too broad for this data. Unset fields are null in planned values, "" in state.
	d := object.get(a, "domain", null)
	is_string(d)
	d != ""
}

public_entry(a) if a.special_group == "allUsers"

deny contains msg if {
	some x in datasets
	some a in x.r.values.access
	public_entry(a)
	msg := sprintf("[%s] %s grants %s to a public or domain-wide principal", [x.view, x.r.address, a.role])
}

email(a) := e if {
	e := object.get(a, "user_by_email", "")
	is_string(e)
} else := ""

allowed_data_classes := {"public", "internal", "restricted"}

deny contains msg if {
	some x in datasets
	x.view == "planned"
	not x.r.values.labels["data-class"] in allowed_data_classes
	msg := sprintf("[planned] %s needs label data-class set to one of %v", [x.r.address, allowed_data_classes])
}

# Restricted data: only service accounts (workloads) may read or write, never humans or groups directly.
deny contains msg if {
	some x in datasets
	x.r.values.labels["data-class"] == "restricted"
	some a in x.r.values.access
	a.role in {"READER", "WRITER"}
	not endswith(email(a), ".gserviceaccount.com")
	msg := sprintf("[%s] %s is restricted but grants %s to a non-workload principal", [x.view, x.r.address, a.role])
}
