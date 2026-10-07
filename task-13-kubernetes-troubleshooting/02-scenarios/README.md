# Triage Scenarios

Session 14, Task 2. Five deliberately broken pods. For each: identify, investigate, find the
root cause, fix it, verify.

All five applied at once:

![All five broken](../screenshots/14-00-all-broken.png)

    NAME                     READY   STATUS             RESTARTS      AGE
    fail-1-crashloop-pod     0/1     Error              3 (43s ago)   70s
    fail-2-imagepull-pod     0/1     ImagePullBackOff   0             70s
    fail-3-pending-pod       0/1     Pending            0             70s
    fail-4-dns-failure-pod   1/1     Running            0             70s
    fail-5-oomkilled-pod     0/1     OOMKilled          3 (37s ago)   70s

Four of them announce themselves in the `STATUS` column. **The fourth does not** — it reads
`Running`, which is the point of including it.

---

## Scenario 1 — CrashLoopBackOff

![CrashLoopBackOff](../screenshots/14-01-crashloop.png)

**Identify.** `RESTARTS 3` and climbing, never ready.

**Investigate.** The container ran, so there are logs:

    $ kubectl logs fail-1-crashloop-pod
    [FATAL ERROR]: DATABASE_URL environment variable is MISSING!

**Root cause.** The application exits 1 when `DATABASE_URL` is unset, and nothing sets it.
`describe` confirms `Reason: Error, Exit Code: 1`.

**Fix.** `fixed.yaml` supplies the variable. In production it would come from a ConfigMap or
a Secret, as in task 11, rather than being inlined.

**Verify.**

    fix-1-crashloop-pod   1/1   Running   0   4s
    Application started successfully!
    Connected to: postgresql://app:secret@postgres.default.svc.cluster.local:5432/appdb

**Worth noting.** The first fix attempt produced a `Running` pod with completely empty logs.
Python buffers stdout when it is not a terminal, so nothing was flushed before the sleep.
Adding `-u` fixed it. An empty log is not proof of a silent process.

---

## Scenario 2 — ImagePullBackOff

![ImagePullBackOff](../screenshots/14-02-imagepull.png)

**Identify.** `ImagePullBackOff`, zero restarts — it never got far enough to restart.

**Investigate.** Logs are unavailable, and the error says why:

    $ kubectl logs fail-2-imagepull-pod
    Error from server (BadRequest): container "web-app" in pod "fail-2-imagepull-pod"
      is waiting to start: trying and failing to pull image

So read events instead:

    Warning  Failed  kubelet  Failed to pull image "yatri-api-service:v999-invalid-tag-does-not-exist":
      ... pull access denied, repository does not exist or may require authorization

**Root cause.** The image does not exist. Note the wording — "does not exist **or may
require authorization**". Docker Hub returns the same error for a missing repository and a
private one you cannot read, so this message does not distinguish a typo from a missing
`imagePullSecret`.

**Fix.** A real, pullable image.

**Verify.** `fix-2-imagepull-pod   1/1   Running`.

---

## Scenario 3 — Pending

![Pending](../screenshots/14-03-pending.png)

**Identify.** `Pending`, and `-o wide` shows `NODE <none>` — never scheduled at all.

**Investigate.** No container means no logs. Events:

    Warning  FailedScheduling  default-scheduler
      0/1 nodes are available: 1 Insufficient cpu, 1 Insufficient memory.

**Root cause.** Put the request and the capacity side by side:

    requested cpu=500  memory=1000Gi

    NODE                   CPU   MEMORY
    devops-control-plane   8     4013352Ki

500 cores against 8, and roughly 1 TB against 4 GB.

**Fix.** Requests that match what nginx actually needs — 100m CPU, 64Mi memory.

**Verify.** Running, and now with a node and an IP.

**Worth noting.** The scheduler works from **requests**, not usage. A node sitting at 5% CPU
can still reject a pod, because every request already granted is reserved whether or not it
is being used.

---

## Scenario 4 — DNS failure

![DNS failure](../screenshots/14-04-dns.png)

**Identify.** This is the interesting one. `kubectl get pods` shows:

    fail-4-dns-failure-pod   1/1   Running   0   4m1s

Perfectly healthy by every signal Kubernetes reports. The failure is only visible in the
logs, and only if you know what success should look like:

    Attempting connection to internal database...
    Process sleeping...

No error, because the script ends in `|| true`.

**Investigate.** Try the lookup from another pod:

    $ kubectl exec fix-3-pending-pod -- nslookup postgres-db-wrong-name.production.svc.cluster.local
    ** server can't find postgres-db-wrong-name.production.svc.cluster.local: NXDOMAIN

**Root cause.** Neither the Service nor the namespace exists:

    $ kubectl get namespace production
    Error from server (NotFound): namespaces "production" not found

**Fix.** Create the Service it should have been calling, and use the correct FQDN —
`postgres-db.default.svc.cluster.local`, matching the pattern from
[`../../task-10-kubernetes-networking-services/fqdn/`](../../task-10-kubernetes-networking-services/fqdn/README.md).

**Verify.**

    $ kubectl get endpoints postgres-db
    postgres-db   10.244.0.97:80

    Name:	postgres-db.default.svc.cluster.local
    Address: 10.96.118.239
    Connecting ...
    HTTP 200

**Worth noting.** The first fix attempt still returned `HTTP 000`, because the client pod
started and ran its curl before the stub backend was Ready. DNS was correct by then; the
endpoint list was still empty. That is the same `000` symptom as the broken-selector Service
in task 10 and the Recreate downtime window in task 9 — three different causes, one
indistinguishable symptom, all of them "no endpoints to forward to".

A readiness probe plus a retry in the client is the real-world answer.

---

## Scenario 5 — OOMKilled

![OOMKilled](../screenshots/14-05-oomkilled.png)

**Identify.** `OOMKilled` with restarts climbing.

**Investigate.** The reason is in the container state, not the logs:

    Last State:     Terminated
      Reason:       OOMKilled
      Exit Code:    137

**Root cause.** Exit code 137 is `128 + 9` — killed by SIGKILL. Not the application's
choice; the kernel's. Compare the ceiling to the demand:

    memory limit=20Mi

against a script allocating 100 × 10MB.

**Fix.** A realistic limit (128Mi) **and** a bounded allocation. Raising the limit alone
would only postpone the failure, since the original loop had no upper bound.

**Verify.**

    fix-5-oomkilled-pod   1/1   Running   0   6s
    allocated 50MB
    Done. Holding steady.

**Worth noting.** Memory limits are enforced by killing, not throttling — unlike CPU limits,
which throttle. There is no graceful degradation and no signal the application can catch.
That asymmetry is why memory limits need headroom and CPU limits can be tighter.

---

## Summary

| # | Symptom | Container ran? | Look at | Root cause |
|---|---|---|---|---|
| 1 | CrashLoopBackOff | yes | `logs` | missing env var |
| 2 | ImagePullBackOff | no | `describe` events | image does not exist |
| 3 | Pending | no | `describe` events | request exceeds node capacity |
| 4 | **Running** | yes | `logs`, then `exec` | wrong Service FQDN |
| 5 | OOMKilled | yes | `describe` last state | limit below actual need |

The row to remember is 4. Kubernetes reported it as healthy throughout.

## Cleanup

    kubectl delete pod -l tier=triage-gauntlet
    kubectl delete svc postgres-db --ignore-not-found
