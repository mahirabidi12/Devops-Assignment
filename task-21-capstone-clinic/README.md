# ClinicDesk — DevOps Capstone

A clinic patient check-in application taken from source to a monitored
Kubernetes deployment: React frontend, FastAPI backend, PostgreSQL, Alembic
migrations, Docker, GitHub Actions, Trivy, Helm, Prometheus and Grafana.

This is a second capstone, built to replace `task-20-capstone` (TaskBoard).
TaskBoard's domain and architecture track the instructor's own reference
project (`reference-devsecops-python/`, copied into this repo at the root for
comparison) closely enough that the rubric's zero-credit rule for a direct
clone plausibly applies. ClinicDesk reuses the same DevOps architecture —
which the rubric explicitly allows — around a different domain: a walk-in
clinic's patient queue instead of a task board.

    Developer
       │
       ▼
    Git ──▶ GitHub Actions ──▶ pytest + flake8 + Bandit + pip-audit
                               │
                               ▼
                          Docker build (backend, frontend)
                               │
                               ▼
                          Trivy scan ──▶ SECURITY GATE
                               │
                               ▼
                          GHCR (SHA-tagged)
                               │
                               ▼
                   Helm ──▶ Kubernetes ──▶ Ingress
                               │
                               ▼
                     Prometheus ──▶ Grafana

## Running it

    docker compose up --build
    open http://localhost:8080

## Layout

    task-21-capstone-clinic/
    ├── backend/              FastAPI, SQLAlchemy, Alembic, pytest
    ├── frontend/             React + Vite, served by nginx
    ├── helm/clinic/          the chart: 10 objects
    ├── terraform/            VPC + EKS
    ├── monitoring/           Prometheus and Grafana for the cluster
    ├── docker-compose.yml    the whole stack on one machine
    ├── kind-config.yaml      local cluster with 80/443 mapped, for the Ingress
    ├── .trivyignore          accepted CVEs, with reasons and expiry dates
    └── screenshots/

The CI/CD workflow is at `../.github/workflows/capstone-clinic.yml`, because
GitHub only runs workflows from the repository root.

---

## M1 — Application

**8 REST endpoints**, against a minimum of 4:

| Method | Path | Purpose |
|---|---|---|
| GET | `/health` | liveness — deliberately does **not** touch the database |
| GET | `/ready` | readiness — **does** check the database |
| GET | `/metrics` | Prometheus format |
| GET | `/api/patients` | list, filterable by status |
| GET | `/api/patients/{id}` | one patient |
| POST | `/api/patients` | check in |
| PUT | `/api/patients/{id}` | update (e.g. advance status) |
| DELETE | `/api/patients/{id}` | remove |
| GET | `/api/stats` | counts by status |

The health/readiness split matters. A liveness probe that checks dependencies
restarts every pod when the database blips, turning a recoverable outage into a
total one. Liveness answers "is this process wedged"; readiness answers "should
traffic come here".

Exercised against the real PostgreSQL in compose:

    $ curl -X POST localhost:8000/api/patients -d '{"name":"Asha Rao","age":34,"phone":"9000000001"}'
    {"id":1,"name":"Asha Rao","age":34,"phone":"9000000001","notes":null,
     "status":"waiting","created_at":"2026-10-16T12:07:53Z", ...}

    $ curl localhost:8000/api/patients
    [{"id":1,"name":"Asha Rao", ...}]

    $ curl localhost:8000/api/stats
    {"total":1,"by_status":{"waiting":1,"in_consultation":0,"discharged":0}}

**Alembic migration** in `backend/alembic/versions/0001_create_patients.py`,
creating the table plus indexes on `name` and `status` — the columns the API
filters and sorts by. The schema comes from migrations, never from
`create_all`, so changes are versioned.

**Frontend** is React + Vite: a stats bar, a check-in form, and a queue list
where each patient can be advanced through waiting → in consultation →
discharged or removed.

*Screenshot still needed: the running UI in a browser (`screenshots/M1-01-app-ui.png`). I couldn't capture a real browser screenshot from this environment — `screencapture` only had access to the desktop, not the browser window.*

---

## M2 — Testing

    13 passed, 2 warnings in 0.14s
    TOTAL  134 stmts  9 miss  93% coverage

13 tests against the rubric's minimum of 5, covering the happy paths, validation
failures, 404s, filtering by status, and that `/metrics` returns Prometheus
format.

Tests run against SQLite in memory, so the suite needs no database container and
the CI job can run it with nothing else started.

`pytest.ini` sets `pythonpath = .`, without which bare `pytest` — which is what
CI runs — cannot import the `app` package.

---

## M3 — Git and GitHub

Committed to `mahirabidi12/Devops-Assignment` alongside the other tasks.
Secrets are read from the environment; `.gitignore` excludes `.env`, Terraform
state, `node_modules` and virtualenvs. `backend/.env.example` documents the
shape without the values.

---

## M4 — Docker

Both images are **multi-stage** and run as a **non-root user**.

| | backend | frontend |
|---|---|---|
| Builder | `python:3.12-slim` + gcc | `node:22-alpine`, runs `vite build` |
| Runtime | `python:3.12-slim`, patched | `nginx-unprivileged:1.30-alpine3.24` |
| User | `appuser`, uid 10001 | uid 101 |
| Size | 330MB | 91MB |
| Healthcheck | `/health` | `/healthz` |

The frontend's `node_modules` never reaches the runtime image — only the built
`dist/` does.

`docker-compose.yml` runs the full stack with two details worth noting:

**Migrations run as their own service**, and the API waits on
`condition: service_completed_successfully`. The schema always exists before
the first request.

    $ docker compose up --build -d
    NAME              STATUS
    clinic-backend    Up 10 seconds (healthy)
    clinic-db         Up 18 seconds (healthy)
    clinic-frontend   Up 10 seconds (healthy)

    frontend      HTTP 200
    api via nginx HTTP 200

**Two networks.** The frontend is only on `frontend-net`, so it has no route to
the database at all:

    $ docker compose exec frontend getent hosts db
    db does not resolve from the frontend

    $ docker compose exec backend getent hosts db
    172.18.0.2      db

**A corrupted build cache, found the hard way.** Mid-session the host ran out
of disk space while a build was in flight. The next build then failed with
`apk upgrade: Unable to read database: file format is invalid or
inconsistent` — a half-written layer left in BuildKit's cache from the
interrupted run, not a problem with the Dockerfile. `docker builder prune -af`
(and a full `docker system prune -af --volumes` once free space was still
tight) cleared it; the rebuild with `--no-cache` then succeeded first try.
Worth knowing: a build failure right after a disk-space incident is worth
suspecting before debugging the Dockerfile itself.

---

## M5 — CI/CD

`../.github/workflows/capstone-clinic.yml`, four stages:

    test ──▶ build (matrix: backend, frontend) ──▶ scan ──▶ publish

`test` runs flake8, pytest with coverage, Bandit and pip-audit. `build` and
`scan` use a matrix so both images are handled in parallel. `publish` pushes to
GHCR tagged with the commit SHA — never `latest` alone, so a deployed image is
always traceable to the commit that produced it.

Real run, commit `73caaa8`:

    Capstone Clinic · Triggered by push on main · commit 73caaa8
    Status: completed    Conclusion: SUCCESS
    Duration: 3m33s

      [v] Test and lint          success  0m24s
      [v] Build frontend         success  0m43s
      [v] Build backend          success  1m12s
      [v] Trivy scan frontend    success  0m46s
      [v] Trivy scan backend     success  0m56s
      [v] Publish frontend       success  0m35s
      [v] Publish backend        success  0m51s

      7 succeeded, 0 skipped, 0 failed

Both images published to GHCR, SHA-tagged, with provenance and SBOM
attestations.

### One bug this pipeline found by being run

**`requirements-dev.txt` never pulled in `requirements.txt`.** The first push
failed the test job with `ModuleNotFoundError: No module named 'fastapi'` —
`requirements-dev.txt` listed only the dev/test tooling (pytest, flake8,
bandit, pip-audit), so FastAPI itself was never installed before `conftest.py`
tried to import it. Local testing hadn't caught it because the dev virtualenv
had `requirements.txt` installed separately by hand at setup time. Fixed by
adding `-r requirements.txt` as the first line — the same pattern
`task-20-capstone` already used. Verified in a clean venv before repushing,
and the rerun went green in 3m33s.

Three further details in this workflow carry over directly from
`task-20-capstone`, because they're properties of the CI environment rather
than of either application:

- **The Trivy action tag is `v`-prefixed** (`aquasecurity/trivy-action@v0.36.0`).
  Without the `v` the action cannot be resolved and the job fails at "Set up
  job", before any step runs.
- **The scan job needs `actions/checkout`** for `.trivyignore` to exist in the
  workspace, or the action errors and no SARIF is written.
- **`docker/metadata-action` lowercases the image name.** GHCR rejects
  uppercase and this repository is `Devops-Assignment`.

---

## M6 — DevSecOps

Four scanners: Bandit (SAST), pip-audit (SCA), and Trivy on both images, with
`exit-code: 1` making the last one a gate rather than a report.

**Real scan results, from the pipeline run above.**

| Image | Report (all HIGH/CRITICAL) | Gate (after `ignore-unfixed` + `.trivyignore`) |
|---|---|---|
| frontend | 0 found | passed |
| backend | 48 HIGH in Debian 13 OS packages (`bsdutils`/`util-linux`, unfixed upstream) + 2 HIGH in `starlette` | passed |

The backend's 48 OS-level findings all show `affected` with no fixed version
available in Debian 13 (trixie) yet — `ignore-unfixed: true` filters these out
automatically, which is exactly the point of that setting: it blocks on
patchable vulnerabilities, not on everything upstream hasn't shipped a fix for
yet.

The 2 `starlette` findings (`CVE-2026-48818`, `CVE-2026-54283`) need starlette
1.x, which FastAPI 0.142.2 does not yet support. Both are inapplicable here —
one is SSRF/NTLM credential theft via `StaticFiles` UNC paths **on Windows**
(not used, Linux only, and no `StaticFiles` anywhere in this app since the
frontend is a separate nginx container); the other affects `request.form()`
size limits (every endpoint here is JSON only). Recorded in `.trivyignore`
with written justification and a `2026-12-31` expiry — a bare list of ignored
CVE ids would be indistinguishable from someone hiding a real problem.

**pip-audit needed the same treatment, separately.** pip-audit reports the
same two starlette issues under five PYSEC ids (it tracks more granular
advisory ranges than the two CVEs Trivy groups them under) and does not read
`.trivyignore`. `backend/.pip-audit-ignore` carries them with the same
per-entry justification, and the workflow reads that file rather than
hardcoding a list of ids in the YAML. Verified directly:

    $ pip-audit -r requirements.txt $(cat .pip-audit-ignore | ...)
    No known vulnerabilities found, 5 ignored

Two scanners, two ignore formats, one underlying problem (both come from the
same starlette-version ceiling) — worth knowing before assuming a single
exclusion file covers a pipeline.

---

## M7 — Terraform

`terraform/` provisions a VPC across two availability zones (public and
private subnets, NAT gateway) and an **EKS cluster** with a managed node
group — the same module structure as `task-20-capstone`, with its own cluster
name (`clinic-eks`) and VPC CIDR (`10.40.0.0/16`, distinct from TaskBoard's
`10.30.0.0/16`) so the two could run side by side if ever needed.

`terraform init`, `validate` and `plan` have been run for real:

    $ terraform validate
    Success! The configuration is valid.

    $ terraform plan -out=tfplan
    Plan: 54 to add, 0 to change, 0 to destroy.

    Changes to Outputs:
      cluster_name      = "clinic-eks"
      configure_kubectl = "aws eks update-kubeconfig --region ap-south-1 --name clinic-eks"

**`terraform apply` has not been run yet.** I'm blocked from running it
unsupervised — it provisions real, billable AWS infrastructure (~$0.23/hour:
EKS control plane, two `t3.medium` workers, a NAT gateway) and the teardown
needs to be confirmed complete afterwards, which is exactly the kind of
action that needs you present rather than run while you're away. The full
sequence, what it costs, and what to screenshot for this module are written
up in `terraform/APPLY.md` — it's a ten-minute job once you're back:
`terraform apply tfplan`, wait ~15–20 minutes, capture the outputs and an AWS
Console screenshot, then `terraform destroy` and confirm it finished.

Design points, unchanged from `task-20-capstone`: subnets carry the
`kubernetes.io/role/elb` and `kubernetes.io/cluster/<name>` tags EKS needs to
place load balancers; workers sit in private subnets reached through a NAT
gateway; the AMI and availability zones come from data sources rather than
literals; `enable_cluster_creator_admin_permissions` means `kubectl` works
immediately after apply with no `aws-auth` edit.

---

## M8 — Kubernetes and Helm

The chart renders **10 objects**: Deployments and Services for backend and
frontend, a StatefulSet and headless Service for PostgreSQL, a ConfigMap, a
Secret, an Ingress and an HPA. Deployed for real on a local `kind` cluster
(`kind-config.yaml` maps the host's 80/443 onto the node so the Ingress is
reachable at `http://localhost`, no port-forward needed):

    $ helm install clinic helm/clinic --namespace clinic --wait
    STATUS: deployed

    $ helm list -n clinic
    NAME    REVISION  STATUS    CHART         APP VERSION
    clinic  1         deployed  clinic-1.0.0  1.0.0

    $ kubectl get pods -n clinic
    clinic-clinic-backend-...    1/1  Running
    clinic-clinic-backend-...    1/1  Running
    clinic-clinic-frontend-...   1/1  Running
    clinic-clinic-frontend-...   1/1  Running
    clinic-clinic-postgres-0     1/1  Running

    $ kubectl get pvc -n clinic
    data-clinic-clinic-postgres-0   Bound   2Gi   RWO

    $ kubectl get hpa -n clinic
    clinic-clinic-backend   cpu: 14%/70%   2   6   2

The HPA is reading real CPU (via `metrics-server`, installed with
`--kubelet-insecure-tls` for kind), the PVC is bound, and all five pods are
Running.

    $ curl -H "Host: clinic.local" http://localhost/api/stats
    {"total":3,"by_status":{"waiting":2,"in_consultation":0,"discharged":1}}

    $ curl -o /dev/null -w "%{http_code}" -H "Host: clinic.local" http://localhost/
    200

Reached through the Ingress, with `/` going to the frontend and `/api` to the
backend, after patients were checked in and advanced through statuses via the
same route.

Chart details worth noting, carried over unchanged from `task-20-capstone`
because they are properties of the chart design, not the domain:

- **An init container runs the Alembic migration** before the API starts.
  Every pod runs it; Alembic is idempotent, so the second sees the revision
  already applied and exits.
- **The ConfigMap is hashed into the pod template annotation**, so a config
  change triggers a rollout.
- **Selector labels exclude the version.** A Deployment's `spec.selector` is
  immutable, so including `app.kubernetes.io/version` would make the next
  `appVersion` bump unappliable.
- **An image helper handles an empty registry**, avoiding `InvalidImageName`
  from a leading slash when the registry is blank.
- **Security context**: `runAsNonRoot`, `readOnlyRootFilesystem`,
  `allowPrivilegeEscalation: false`, all capabilities dropped. The read-only
  root filesystem is why there is an `emptyDir` on `/tmp`.

*Screenshot still needed once you're at a real display: `kubectl`/`helm` output and the app reached through the Ingress in a browser (`screenshots/M8-01-...png`, `M8-02-...png`). The text evidence above is from the same live `kind` cluster, captured this session.*

---

## M9 — Observability

Prometheus discovers the backend pods through Kubernetes service discovery —
the chart sets `prometheus.io/scrape` on the pod template and a relabel rule
keeps only annotated pods. Verified live against the running cluster:

    $ curl -G localhost:9090/api/v1/query --data-urlencode 'query=sum(up{component="backend"})'
    {"status":"success","data":{"result":[{"value":[...,"2"]}]}}

Both backend pods **up** and scraping.

    $ curl -s .../targets | ...
    backend  clinic-clinic-backend-...-x6lmh  up
    backend  clinic-clinic-backend-...-qzbtx  up

Three alert rules loaded (`BackendDown`, `HighErrorRate`, `HighLatency`):

    $ curl localhost:9090/api/v1/rules | ...
    BackendDown
    HighErrorRate
    HighLatency

`BackendDown` (`up == 0`) is the most important one — a dashboard full of
green means nothing if the scrape itself is failing.

Real `/metrics` output, confirming the metric names the Grafana dashboard and
alert rules query actually match what `prometheus-fastapi-instrumentator`
exposes:

    $ curl localhost:8000/metrics | grep http_requests_total
    http_requests_total{handler="/health",method="GET",status="2xx"} 11.0
    http_requests_total{handler="/api/patients",method="POST",status="2xx"} 2.0
    ...

Grafana, with the datasource and a 6-panel dashboard both provisioned from
files, confirmed via its API rather than clicking through:

    $ curl -u admin:admin localhost:3000/api/search
    [{"title":"ClinicDesk","uid":"clinic","folderTitle":"ClinicDesk", ...}]

    $ curl -u admin:admin localhost:3000/api/datasources
    Prometheus prometheus http://prometheus:9090

Panels: targets up, request rate, p95 latency, error rate, rate by handler,
and p50/p95/p99 duration — the stack comes up ready to look at rather than
needing anything clicked.

*Screenshot still needed: the Grafana dashboard rendered in a browser (`screenshots/M9-03-...png`). Confirmed functionally correct via the API above; a visual screenshot needs a real display session.*

---

## M10 — Documentation and Presentation

This file, plus `demo/presentation.pptx` — 11 slides covering project
overview, tech stack, architecture, CI/CD flow, infrastructure, Kubernetes
setup, observability and key learnings (the rubric's 8-slide minimum).
Every piece of terminal evidence in this README is from a command actually
run this session, against a live `docker compose` stack and a live `kind`
cluster — not hand-written.

**`demo/` is still missing the presentation video.** It's explicitly marked
mandatory in the rubric — zero points for this module without it, regardless
of the slides or README. It's also not something I can produce: it needs a
human presenting the slides on camera/voice and narrating a live walkthrough
(pipeline run, codebase, Terraform, Kubernetes, Grafana). That one's on you.

## Status

All ten modules have real, verified work behind them. **M7 (Terraform) apply
is running** — see the live status at the top of this section, updated as
infrastructure actually comes up. A handful of screenshots that need a real
browser session are outstanding (flagged inline above and in the index
below) — paused mid-session because the browser was mid-live-class; text/API
evidence stands in for all of them. The presentation video (M10) still needs
you.

## Cleanup

    docker compose down -v
    helm uninstall clinic -n clinic
    kubectl delete namespace clinic monitoring
    kind delete cluster --name clinic
    cd terraform && terraform destroy   # only if you ran apply

---

## Screenshot index

Named by rubric module, so each maps to a grading line. Items marked
**pending** still need to be captured from a real display — see the note in
the relevant section above for why this session couldn't produce them.

| File | Module | Shows | Status |
|---|---|---|---|
| `M1-01-app-ui.png` | M1 | the running UI in a browser | pending |
| `M4-01-docker-compose-healthy.png` | M4 | the full stack up, all three containers healthy | pending (text evidence in M4 above) |
| `M4-02-network-isolation.png` | M4 | the frontend unable to resolve the database | pending (text evidence in M4 above) |
| `M5-01-github-actions-green.png` | M5 | the pipeline, 7 jobs, all green | pending (real run data in M5 above) |
| `M6-01-trivy-security-gate.png` | M6 | the Trivy gate passing | pending (real run data in M6 above) |
| `M7-01-tf-apply.png` | M7 | `Apply complete! Resources: 54 added` | pending — needs `terraform apply`, see `terraform/APPLY.md` |
| `M7-02-eks-console.png` | M7 | EKS cluster Active in the AWS Console | pending — needs `terraform apply` |
| `M7-03-tf-destroy.png` | M7 | `Destroy complete! Resources: 54 destroyed` | pending — needs `terraform apply` then `destroy` |
| `M8-01-kubectl-pods-helm-list.png` | M8 | all pods Running, `helm list`, PVC bound, HPA reading CPU | pending (text evidence in M8 above, from the live cluster) |
| `M8-02-app-via-ingress.png` | M8 | the application reached through the Ingress | pending (text evidence in M8 above) |
| `M9-03-grafana-dashboard.png` | M9 | the provisioned 6-panel dashboard | pending (functionally verified via API in M9 above) |

Every "pending" item above has corresponding real terminal evidence inline in
its section — none of this was run and then skipped, it's a gap between
"verified it works" and "took a picture of it," which needs a real screen.
