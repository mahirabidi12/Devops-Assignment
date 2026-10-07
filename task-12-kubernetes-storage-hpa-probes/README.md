# Kubernetes Storage, HPA & Probes

Session 13. Three tasks, each in its own folder, all run on a single node kind cluster
running `v1.37.0`.

| Folder | Task | Covers |
|---|---|---|
| [`01-kubernetes-volumes/`](01-kubernetes-volumes/README.md) | Task 1 | emptyDir, hostPath, PersistentVolume, PersistentVolumeClaim, StorageClass, dynamic provisioning |
| [`02-hpa/`](02-hpa/README.md) | Task 2 | HPA configured, load generated, CPU observed, pods scaled up and back down |
| [`03-probes/`](03-probes/README.md) | Task 3 | readiness, liveness and startup probes |
| [`mini-project/`](mini-project/README.md) | Task 3 | all of the above in one namespaced deployment |

## Cluster preparation

kind does not ship metrics-server, and without it `kubectl top` and the HPA have no data.
Installing it takes one extra patch because kind's kubelet certificates are self-signed:

    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
    kubectl patch deployment metrics-server -n kube-system --type=json \
      -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

## Findings worth highlighting

Three things came out of running this rather than reading it.

**A PVC that looks like it should bind to a PV does not.** Applying `pv.yaml` and `pvc.yaml`
together left the claim `Pending` and the volume `Available`. The claim inherited the
default StorageClass `standard` while the hand-written PV sat in the empty class `""`, so
they could never match. Creating a consumer pod then provisioned a brand new 500Mi volume
dynamically and ignored the 1Gi one entirely. Leaving `storageClassName` off a PVC is not
the same as setting it to `""`.

**A load generator can take out CoreDNS.** Six pods running `wget` in a tight loop against a
Service *name* meant a DNS query per request, and the generators started failing with
`bad address`. Targeting the ClusterIP directly fixed it. A retry loop without backoff can
break a shared dependency and surface the failure somewhere unrelated.

**Scale-up is immediate, scale-down is not.** After the load stopped, CPU read 0% while the
replica count stayed at 4 for five minutes before dropping. That is the stabilisation
window, and the asymmetry is deliberate — quick to grow, slow to shrink, so load that comes
and goes does not cause thrashing.

**`kubectl apply -f <dir>` has no dependency ordering.** It submits files alphabetically, so
`deployment.yaml` was rejected for a namespace that `namespace.yaml` had not created yet.
Running it twice works, which is why scrappy scripts often do.

## Screenshots

| File | Shows |
|---|---|
| `13-01-emptydir-hostpath.png` | writing to both, and reading the hostPath file from the node |
| `13-02-pv-pvc-binding.png` | the static PV ignored, a dynamic one provisioned instead |
| `13-03-persistence.png` | PVC data surviving pod deletion, emptyDir not |
| `13-04-hpa-scale-up.png` | HPA at 4 replicas under load, with the rescale events |
| `13-05-hpa-scale-down.png` | the full cycle: 1 → 4 → 3 → 1 |
| `13-06-mini-project.png` | the namespaced stack, including the apply-ordering failure |

## Cleanup

    kubectl delete namespace production-webapp
    kubectl delete -f 01-kubernetes-volumes/ -f 02-hpa/ -f 03-probes/ --ignore-not-found
    kubectl delete pv student-pv --ignore-not-found
