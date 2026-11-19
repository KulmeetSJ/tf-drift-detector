#!/usr/bin/env python3
"""Build a drift report from Terraform plan JSON and Conftest results.

    report.py --drift drift.json --plan plan.json [--policy conftest.json] \
              [--out report.md] [--metrics metrics.json]

drift.json   `terraform show -json` of `terraform plan -refresh-only`  (real world vs state)
plan.json    `terraform show -json` of `terraform plan`                (code vs real world)
conftest.json `conftest test -o json plan.json`

Exit code is always 0 for a successful report. The status is in metrics.json, so the workflow decides
what to do with it. Drift is read from the JSON, NOT from -detailed-exitcode: a refresh-only plan
with a data source exits 2 even when nothing changed.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

NOOP = {("no-op",), ("read",)}

# Attributes the provider recomputes on any write. They change without anyone touching the resource
# (e.g. the project IAM etag changes when ANY binding changes), so they are not drift on their own.
NOISE = {"etag", "last_modified_time", "effective_labels", "terraform_labels"}


def changed_paths(before, after, prefix=""):
    """Paths (a.b[0].c) whose values differ between two JSON values."""
    if isinstance(before, dict) and isinstance(after, dict):
        out = []
        for k in sorted(set(before) | set(after)):
            out += changed_paths(before.get(k), after.get(k), f"{prefix}.{k}" if prefix else k)
        return out
    if isinstance(before, list) and isinstance(after, list) and len(before) == len(after):
        out = []
        for i, (b, a) in enumerate(zip(before, after)):
            out += changed_paths(b, a, f"{prefix}[{i}]")
        return out
    if before == after or (before in (None, "", [], {}) and after in (None, "", [], {})):
        return []
    return [prefix or "(value)"]


def collapse(paths, depth=1):
    """Group paths by their first `depth` segments: access[3].role -> access."""
    seen = []
    for p in paths:
        head = p.split(".")[0].split("[")[0] if depth == 1 else p
        if head not in seen:
            seen.append(head)
    return seen


def resource_drift(drift_plan):
    rows = []
    for rc in drift_plan.get("resource_drift", []) or []:
        ch = rc["change"]
        actions = tuple(ch["actions"])
        if actions in NOOP:
            continue
        if actions == ("delete",):
            attrs = ["(deleted outside Terraform)"]
        else:
            attrs = [a for a in collapse(changed_paths(ch.get("before"), ch.get("after"))) if a not in NOISE]
            if not attrs:
                continue
        rows.append({"address": rc["address"], "type": rc["type"], "action": "/".join(actions), "attributes": attrs})
    return rows


def bindings_to_pairs(bindings):
    return {(b["role"], m) for b in (bindings or []) for m in b.get("members", [])}


def unmanaged_iam_changes(drift_plan):
    """Diff of the live project IAM policy (output live_project_bindings) since the last apply."""
    oc = (drift_plan.get("output_changes") or {}).get("live_project_bindings")
    if not oc or tuple(oc["actions"]) in NOOP:
        return [], []
    before, after = bindings_to_pairs(oc.get("before")), bindings_to_pairs(oc.get("after"))
    return sorted(after - before), sorted(before - after)


def pending_changes(plan, drifted):
    rows = []
    for rc in plan.get("resource_changes", []) or []:
        actions = tuple(rc["change"]["actions"])
        if actions in NOOP:
            continue
        rows.append({
            "address": rc["address"],
            "action": "/".join(actions),
            "reverts_drift": rc["address"] in drifted,
        })
    return rows


def policy_failures(conftest):
    out = []
    for f in conftest or []:
        for fail in f.get("failures") or []:
            out.append(fail["msg"])
    return sorted(set(out))


def build(drift_plan, plan, conftest):
    drift = resource_drift(drift_plan)
    drifted = {d["address"] for d in drift}
    added, removed = unmanaged_iam_changes(drift_plan)
    pending = pending_changes(plan, drifted)
    code_changes = [p for p in pending if not p["reverts_drift"]]
    violations = policy_failures(conftest)

    # Bindings managed authoritatively by Terraform already show up as resource drift; keep the IAM
    # section for grants Terraform does not manage, so nothing is reported twice.
    managed_roles = {
        r["values"]["role"]
        for r in (plan.get("planned_values", {}).get("root_module", {}).get("resources", []) or [])
        if r.get("type") == "google_project_iam_binding"
    }
    added = [p for p in added if p[0] not in managed_roles]
    removed = [p for p in removed if p[0] not in managed_roles]

    status = "clean"
    if drift or added or removed:
        status = "drift"
    elif code_changes:
        status = "changes"
    if violations:
        status = "violations" if status == "clean" else status + "+violations"

    metrics = {
        "status": status,
        "drifted_resources": len(drift),
        "unmanaged_iam_changes": len(added) + len(removed),
        "pending_code_changes": len(code_changes),
        "policy_violations": len(violations),
        "terraform_version": plan.get("terraform_version"),
    }
    return metrics, render(metrics, drift, added, removed, pending, violations)


def render(m, drift, added, removed, pending, violations):
    icon = {"clean": "✅"}.get(m["status"], "⚠️")
    L = [f"## {icon} Drift report: `{m['status']}`", ""]
    L += [
        "| Check | Count |", "|---|---|",
        f"| Resources drifted (changed outside Terraform) | {m['drifted_resources']} |",
        f"| Unmanaged project IAM grants added/removed | {m['unmanaged_iam_changes']} |",
        f"| Unapplied code changes | {m['pending_code_changes']} |",
        f"| Policy violations | {m['policy_violations']} |", "",
    ]
    if drift:
        L += ["### Drift: real world ≠ Terraform state", "", "| Resource | Changed attributes |", "|---|---|"]
        L += [f"| `{d['address']}` | {', '.join(f'`{a}`' for a in d['attributes'])} |" for d in drift]
        L += [""]
    if added or removed:
        L += ["### Project IAM changed outside Terraform", "", "| Change | Role | Member |", "|---|---|---|"]
        L += [f"| added | `{r}` | `{m_}` |" for r, m_ in added]
        L += [f"| removed | `{r}` | `{m_}` |" for r, m_ in removed]
        L += [""]
    if pending:
        L += ["### Plan: what `terraform apply` would do", "", "| Resource | Action | Why |", "|---|---|---|"]
        L += [f"| `{p['address']}` | {p['action']} | {'reverts drift' if p['reverts_drift'] else 'code change not yet applied'} |" for p in pending]
        L += [""]
    if violations:
        L += ["### Policy violations", ""] + [f"- {v}" for v in violations] + [""]
    return "\n".join(L)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--drift", required=True, type=Path)
    ap.add_argument("--plan", required=True, type=Path)
    ap.add_argument("--policy", type=Path)
    ap.add_argument("--out", type=Path)
    ap.add_argument("--metrics", type=Path)
    a = ap.parse_args(argv)
    conftest = json.loads(a.policy.read_text()) if a.policy and a.policy.exists() else []
    metrics, md = build(json.loads(a.drift.read_text()), json.loads(a.plan.read_text()), conftest)
    (a.out.write_text(md + "\n") if a.out else sys.stdout.write(md + "\n"))
    if a.metrics:
        a.metrics.write_text(json.dumps(metrics, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
