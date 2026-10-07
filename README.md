# Scaler DevOps Homework

**Mahir Abidi — 24BCS10125**

Every session of the DevOps course, each in its own folder. The work was carried
out rather than described: every command in these documents was run, and every
screenshot is of real output.

## Index

Folders are numbered `task-N`, where **task-N corresponds to session N+1**.

| Session | Topic | Folder |
|---|---|---|
| 2 | Linux Fundamentals | [task-1-linux-basics](task-1-linux-basics/) |
| 3 | Shell Scripting | [task-2-shell-scripting](task-2-shell-scripting/) |
| 4 | Networking | [task-3-networking](task-3-networking/) |
| 5 | Git and GitHub | [task-4-git](task-4-git/) |
| 6–7 | Docker Fundamentals | [task-5-docker](task-5-docker/) |
| 6–7 | Docker Images / Multi-stage | [task-6-docker-multistage](task-6-docker-multistage/) |
| 8 | Docker Networking and Volumes | [task-7-docker-networking-volume](task-7-docker-networking-volume/) |
| 9 | Kubernetes Fundamentals | [task-8-kubernetes-fundamentals](task-8-kubernetes-fundamentals/) |
| 10 | Pods, ReplicaSets and Deployments | [task-9-kubernetes-pods-replicasets-deployments](task-9-kubernetes-pods-replicasets-deployments/) |
| 11 | Kubernetes Networking and Services | [task-10-kubernetes-networking-services](task-10-kubernetes-networking-services/) |
| 12 | Ingress, ConfigMaps and Secrets | [task-11-kubernetes-ingress-configmaps-secrets](task-11-kubernetes-ingress-configmaps-secrets/) |
| 13 | Storage, HPA and Probes | [task-12-kubernetes-storage-hpa-probes](task-12-kubernetes-storage-hpa-probes/) |
| 14 | Kubernetes Troubleshooting | [task-13-kubernetes-troubleshooting](task-13-kubernetes-troubleshooting/) |
| 15 | Helm | [task-14-helm](task-14-helm/) |
| 16 | CI/CD and GitHub Actions | [task-15-cicd-github-actions](task-15-cicd-github-actions/) |
| 17 | Complete CI/CD and DevSecOps | [task-16-devsecops](task-16-devsecops/) |
| 18 | Terraform and IaC | [task-17-terraform-iac](task-17-terraform-iac/) |
| 19 | Cloud and Terraform in Action | [task-18-cloud-terraform](task-18-cloud-terraform/) |
| 20 | Monitoring, Observability and GitOps | [task-19-monitoring-observability-gitops](task-19-monitoring-observability-gitops/) |
| 21 | **Final Capstone — TaskBoard** | [task-20-capstone](task-20-capstone/) |

## The capstone

[**task-20-capstone**](task-20-capstone/) is the final project: a React +
FastAPI + PostgreSQL application taken from source to a monitored Kubernetes
deployment, with Alembic migrations, 13 tests, multi-stage non-root images, a
GitHub Actions pipeline with a Trivy security gate, a Helm chart, Terraform for
VPC + EKS, and Prometheus with Grafana.

## Pipelines

Workflows live in [`.github/workflows/`](.github/workflows/), scoped with
`paths:` filters so each runs only for its own task.

| Workflow | For | Covers |
|---|---|---|
| `ci.yml` | session 16 | lint, a three-version test matrix, image build |
| `cd.yml` | session 16 | publish to GHCR, gated deploy |
| `devsecops.yml` | session 17 | Gitleaks, Bandit, pip-audit, Trivy gate |
| `capstone.yml` | session 21 | test, build, scan, publish for both images |

## Environment

Most Kubernetes work ran on a local **kind** cluster (`v1.37.0`) on Apple
Silicon. Where that forced a change from the course material it is recorded in
the relevant document — for example `mysql:8.0` in place of `mysql:5.7`, which
has no arm64 build.

## What is not finished

Stated here rather than left to be discovered:

- **Session 17's pipeline** has not had a green run. Six of its eight jobs pass;
  the Trivy job fails for a reason that could not be diagnosed without
  authenticated access to the job logs.
- **Session 19's Terraform** has been planned but not applied, so no AWS
  resources were created for it.
- **The capstone's EKS infrastructure** validates and plans but has not been
  applied. Instructions and the cost breakdown are in
  [task-20-capstone/terraform/APPLY.md](task-20-capstone/terraform/APPLY.md).

Everything else in every session was run, captured and documented.
