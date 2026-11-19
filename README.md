# tf-drift-detector

Scheduled Terraform drift detection with policy-as-code (Conftest/Rego) in GitHub Actions.
It separates **true drift** (someone changed the cloud by hand) from **unapplied code changes**, and opens one GitHub issue per drift state.

> Work in progress. All resources are synthetic sandbox resources. Every number will be a personal-project benchmark.
