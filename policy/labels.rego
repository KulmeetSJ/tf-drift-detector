package main

import data.lib
import rego.v1

required_labels := {"owner", "env", "cost-center"}

labelable := {"google_bigquery_dataset"}

deny contains msg if {
	some x in lib.resources
	x.r.type in labelable
	some l in required_labels
	not x.r.values.labels[l]
	msg := sprintf("[%s] %s is missing required label %q", [x.view, x.r.address, l])
}
