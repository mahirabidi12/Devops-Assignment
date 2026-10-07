# Probes

Session 13, Task 3 (probes portion).

The three probe types were demonstrated in detail, each running on a real cluster with
captured output, as part of the pod lifecycle work in task 9:

**[`../../task-9-kubernetes-pods-replicasets-deployments/pod-lifecycle/README.md`](../../task-9-kubernetes-pods-replicasets-deployments/pod-lifecycle/README.md)**
— sections 7, 8 and 9.

That write-up shows a readiness probe holding a pod at `0/1` until it passes, a liveness
probe failing twice and triggering `Killing ... will be restarted`, and a startup probe
absorbing six failures over 31 seconds without a restart.

The manifests here are the session 13 copies, kept so this task is self-contained.

## The one-line summary

| Probe | On failure | Exists to |
|---|---|---|
| **readiness** | pod removed from Service endpoints | stop traffic reaching a pod that cannot serve |
| **liveness** | container killed and restarted | recover a wedged process |
| **startup** | container killed once the budget is exhausted | protect a slow starter from the liveness probe |

## Why all three together

While a **startup** probe is running, the readiness and liveness probes are disabled
entirely. That is the point of it: a slow-booting application gets a generous budget
(`periodSeconds × failureThreshold`) without forcing you to set a long liveness
`initialDelaySeconds`, which would blind the liveness probe to real hangs later.

Once startup succeeds, readiness and liveness take over with tight settings.

The mini-project in `../mini-project/` uses exactly this arrangement:

    startupProbe:    failureThreshold: 30, periodSeconds: 2    → 60 second boot budget
    readinessProbe:  initialDelaySeconds: 5, failureThreshold: 2
    livenessProbe:   initialDelaySeconds: 5, failureThreshold: 3

Verified on the running pods:

    $ kubectl get pod -n production-webapp -o custom-columns=NAME:...,STARTUP:...,READINESS:...,LIVENESS:...
    NAME                      STARTUP   READINESS   LIVENESS
    web-app-d45775485-9blc4   /         /           /
    web-app-d45775485-gqtwt   /         /           /

## The mistake worth avoiding

Pointing a liveness probe at an endpoint that checks dependencies. If `/health` returns 503
because the database is briefly unreachable, a liveness probe will restart every pod in the
deployment — turning a recoverable blip into a total outage, and adding a thundering herd of
reconnects on top.

Liveness should test only whether *this process* is wedged. Dependency checks belong in
readiness, where the consequence is being taken out of load balancing rather than killed.

## Probe types

All three support the same three mechanisms:

| Mechanism | Succeeds when |
|---|---|
| `httpGet` | status is 200–399 |
| `tcpSocket` | the port accepts a connection |
| `exec` | the command exits 0 |

`exec` is the most expensive — it starts a process in the container on every check — so a
one-second period on an `exec` probe is a measurable cost at scale.

## Cleanup

    kubectl delete -f .
