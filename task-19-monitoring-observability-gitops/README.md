# Monitoring, Observability & GitOps

Session 20. Three tasks, all run for real — Prometheus and Grafana in Docker, ArgoCD on the
kind cluster.

| Folder | Task | Covers |
|---|---|---|
| [`01-monitoring/`](01-monitoring/README.md) | Task 1 | Prometheus, Grafana, node-exporter, metrics, alert rules, CPU and memory |
| [`02-observability/`](02-observability/README.md) | Task 2 | the three pillars, and how they differ from monitoring |
| [`03-gitops/`](03-gitops/README.md) | Task 3 | ArgoCD, git as source of truth, sync and self-heal |

## Findings worth highlighting

**A monitoring system can fail silently, and that is its worst failure mode.**
`prometheus.yml` referenced an alerts file that the compose file never mounted. Prometheus
started cleanly and the rules API returned `"status": "success"` with zero rules. Nothing was
broken, nothing was alerting, and the symptom was *less noise* — which looks like things
going well.

**`TargetDown` is the alert that matters most.** A dashboard full of green is meaningless if
the scrape is failing; you are looking at stale data, not healthy systems. Alerting on the
absence of data is the thing people forget.

**`for:` is what makes alerts survivable.** `HighCpuUsage` was genuinely `pending` when
captured, because the machine was busy building container images. Without the two-minute
window every build would have paged someone.

**ArgoCD needs `kubectl apply --server-side`.** The plain form fails with
`metadata.annotations: Too long`, because client-side apply stores the whole previous object
in an annotation and the ApplicationSet CRD alone exceeds the 256KB limit.

**Self-heal means manual fixes do not survive.** Scaling to 5 by hand was reverted to 1
within the reconcile interval. That is the point, and it is also the thing that catches
people out during an incident.

**Sync status and health status are different questions.** `Synced` + `Progressing` means
the cluster matches git and git describes something still starting. Helm's single `deployed`
status conflates the two, which is how [task 14](../task-14-helm/02-rollback/README.md)
reported success for a release stuck in `ImagePullBackOff`.

## Screenshots

| File | Shows |
|---|---|
| `20-01-prometheus-targets.png` | the three containers up, both targets scraping, `up == 1` |
| `20-02-metrics-alerts.png` | real CPU and memory figures, four alert rules with states |
| `20-03-argocd-sync.png` | an Application synced from git, with no deploy command |
| `20-04-self-heal.png` | a manual scale to 5 reverted to the 1 git specifies |

## Cleanup

    cd 01-monitoring && docker compose down -v
    kubectl delete -f 03-gitops/argocd-application-demo.yaml
    kubectl delete namespace argocd gitops-demo
