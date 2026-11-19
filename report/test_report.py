"""Unit tests for report.py. Fixtures are real (sanitized) plans from the sandbox project:
clean_*  - right after apply
drift_*  - after scripts/induce_drift.sh all (7 console-style changes)
"""
import json
import unittest
from pathlib import Path

import report

FX = Path(__file__).parent / "fixtures"


def load(name):
    return json.loads((FX / f"{name}.json").read_text())


class CleanProject(unittest.TestCase):
    def test_clean_project_reports_clean(self):
        # The refresh-only plan exits 2 here (data source), yet nothing drifted.
        m, md = report.build(load("clean_refresh"), load("clean_plan"), [])
        self.assertEqual(m["status"], "clean")
        self.assertEqual((m["drifted_resources"], m["unmanaged_iam_changes"], m["pending_code_changes"]), (0, 0, 0))
        self.assertIn("✅", md)


class InducedDrift(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.metrics, cls.md = report.build(load("drift_refresh"), load("drift_plan"), [])
        cls.drift = {d["address"]: d["attributes"] for d in report.resource_drift(load("drift_refresh"))}

    def test_all_seven_scenarios_detected(self):
        # 6 managed resources drifted + 1 grant on a role Terraform does not manage
        self.assertEqual(self.metrics["drifted_resources"], 6)
        self.assertEqual(self.metrics["unmanaged_iam_changes"], 1)
        self.assertEqual(self.metrics["status"], "drift")

    def test_exact_attribute_per_scenario(self):
        self.assertEqual(self.drift, {
            "google_bigquery_dataset.raw": ["access"],                       # public-dataset
            "google_bigquery_dataset.reporting": ["labels"],                 # label
            "google_project_iam_binding.job_user": ["members"],              # binding-member
            "google_project_iam_custom_role.dataset_auditor": ["permissions"],  # role-escalation
            "google_service_account.analyst": ["disabled"],                  # sa-disabled
            "google_service_account.etl": ["description"],                   # sa-description
        })

    def test_etag_only_change_is_not_drift(self):
        # dataset_auditor binding's etag changed only because another binding changed.
        self.assertNotIn("google_project_iam_binding.dataset_auditor", self.drift)

    def test_unmanaged_editor_grant_reported_once(self):
        added, removed = report.unmanaged_iam_changes(load("drift_refresh"))
        editor = [p for p in added if p[0] == "roles/editor"]
        self.assertEqual(editor, [("roles/editor", "serviceAccount:reporting-app@tf-drift-sandbox-ntd6t.iam.gserviceaccount.com")])
        # the jobUser member is already resource drift on the authoritative binding: not duplicated
        self.assertNotIn("roles/bigquery.jobUser", self.md.split("### Project IAM")[1].split("###")[0])

    def test_plan_changes_marked_as_reverting_drift_not_code(self):
        self.assertEqual(self.metrics["pending_code_changes"], 0)
        self.assertIn("reverts drift", self.md)


class Helpers(unittest.TestCase):
    def test_changed_paths_nested_and_lists(self):
        b = {"a": 1, "l": [{"x": 1}, {"x": 2}], "s": ""}
        a = {"a": 1, "l": [{"x": 1}, {"x": 3}], "s": None}
        self.assertEqual(report.changed_paths(b, a), ["l[1].x"])

    def test_collapse_groups_by_top_level_attribute(self):
        self.assertEqual(report.collapse(["access[3].role", "access[4].role", "labels.env"]), ["access", "labels"])

    def test_code_change_counted_separately_from_drift(self):
        plan = {"resource_changes": [
            {"address": "a.new", "change": {"actions": ["create"]}},
            {"address": "a.drifted", "change": {"actions": ["update"]}},
            {"address": "a.same", "change": {"actions": ["no-op"]}},
        ]}
        rows = report.pending_changes(plan, {"a.drifted"})
        self.assertEqual([(r["address"], r["reverts_drift"]) for r in rows], [("a.new", False), ("a.drifted", True)])

    def test_policy_failures_deduplicated(self):
        conf = [{"failures": [{"msg": "x"}, {"msg": "x"}]}, {"failures": None}]
        self.assertEqual(report.policy_failures(conf), ["x"])

    def test_violations_status_when_otherwise_clean(self):
        m, _ = report.build(load("clean_refresh"), load("clean_plan"), [{"failures": [{"msg": "bad"}]}])
        self.assertEqual(m["status"], "violations")


if __name__ == "__main__":
    unittest.main()
