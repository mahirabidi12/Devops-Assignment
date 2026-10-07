# Kubernetes Object Comparison

Notes for Session 11, Task 2. The behaviour described here is what was actually observed
while doing tasks 9 and 10 of this homework; the command output backing each claim is in
`../README.md` and `../../task-10-kubernetes-networking-services/README.md`.

---

## 1. Deployment vs ReplicaSet

### Purpose

A **ReplicaSet** has exactly one job: keep N copies of a pod running. It has no concept of
versions, updates or history. Give it a pod template and a count, and it will hold that
count.

A **Deployment** sits one level above and adds *change* management. It describes the
desired end state and moves the cluster there gradually, keeping the previous state
around so you can go back.

### Pod management

Neither object creates pods the way you might expect.

- The ReplicaSet creates pods directly and owns them through its label selector.
- The Deployment creates **ReplicaSets**, and lets them create the pods. It never touches
  a pod itself.

This was visible in task 9. After applying the Deployment there were two ReplicaSets in
the cluster: `myapp-5b9587f95d`, created by the Deployment with a hash of the pod template
in its name, and `myapp-rs`, the standalone one applied separately.

### Scaling

Both scale by changing `replicas`, and both react to pods disappearing. Deleting a pod
from the ReplicaSet in task 9 produced a replacement within seconds — a *new* pod with a
different name and IP, not a restart of the old one.

The difference is who you talk to. With a Deployment you scale the Deployment and it
passes the number down to its current ReplicaSet. Scaling the ReplicaSet underneath a
Deployment directly does not stick, because the Deployment controller will correct it.

### Rolling updates

This is the real dividing line.

A ReplicaSet **cannot** update. Change the image in its template and existing pods keep
running the old image, because the ReplicaSet only counts pods, it does not compare them
to the template.

A Deployment handles this by creating a second ReplicaSet for the new template and
shifting replicas across. From task 9:

    myapp-5b9587f95d   0   0   0    # old template, scaled to zero
    myapp-754cfcff96   3   3   3    # new template, scaled up

Pods were replaced a few at a time, never all at once, which is what makes it zero
downtime.

### The relationship

    Deployment ──owns──► ReplicaSet ──owns──► Pods
       │                     │
       │                     └─ one per version of the pod template
       └─ handles updates, rollout history, rollback

The old ReplicaSet is kept at zero replicas rather than deleted, and that is precisely
what makes rollback cheap. `kubectl rollout undo` scales the old one back up — nothing is
rebuilt and no image is pulled again. Task 9 shows the image going from `nginx:1.27-alpine`
back to `nginx` in seconds.

### Summary

| | ReplicaSet | Deployment |
|---|---|---|
| Keeps N pods alive | yes | yes, through a ReplicaSet |
| Creates pods | directly | indirectly |
| Can change the image | no | yes |
| Rollout history | no | yes |
| Rollback | no | yes, one command |
| Written by hand in practice | rarely | almost always |

---

## 2. Deployment vs DaemonSet vs StatefulSet

All three manage pods. They differ in *how many*, *where*, and *whether the pods have
identities*.

### Use cases

| | Typical workload |
|---|---|
| **Deployment** | stateless things you can have any number of — web servers, APIs, workers |
| **DaemonSet** | per-node infrastructure — log collectors (Fluentd, Promtail), node metrics (node-exporter), storage daemons, CNI agents |
| **StatefulSet** | clustered data stores — MySQL, Cassandra, MongoDB, Kafka, ZooKeeper, Redis |

The rule of thumb: if the pods are interchangeable use a Deployment; if you need one per
machine use a DaemonSet; if each pod is a distinct member of a cluster use a StatefulSet.

### Pod creation

**Deployment** — you set the count, the scheduler places the pods wherever it likes, and
they start in parallel. Names get a random suffix: `myapp-6b5dcdc46d-b9wfz`.

**DaemonSet** — you do not set a count at all. The controller derives it from the nodes
and keeps one pod per eligible node, adding pods as nodes join.

Task 9 showed why "eligible" matters. On a three node cluster the DaemonSet reported
`DESIRED 2`, not 3, because the control plane node carries:

    Taints:  node-role.kubernetes.io/control-plane:NoSchedule

so it is excluded from the count. A DaemonSet that genuinely must run everywhere, like a
CNI plugin, declares a toleration for that taint.

**StatefulSet** — pods are created **in order**, 0 then 1 then 2, each waiting for the
previous to be Ready. The `rollout status` output in task 9 counts down from three pods
waiting, to two, to one. Deletion runs in reverse, highest ordinal first.

### Scaling

| | Scaling |
|---|---|
| Deployment | change `replicas`, pods come and go in any order |
| DaemonSet | not scaled by you — it follows the node count |
| StatefulSet | change `replicas`, but strictly ordered: scaling to 5 adds 3 then 4; scaling down removes 4 then 3 |

### Networking

| | Identity on the network |
|---|---|
| Deployment | none. Reached through a Service that load balances across whichever pods are ready |
| DaemonSet | usually reached on the node itself, often through `hostPort` or `hostNetwork`, since the point is the local node |
| StatefulSet | each pod gets a stable DNS name through a headless Service: `mysql-0.mysql.default.svc.cluster.local` |

The StatefulSet row only works because of the headless Service named in `serviceName`.
Task 10 confirmed it: `web-stateful-0.web-service-headless...` resolved to exactly that
pod's IP, while the Service name itself returned all three pod IPs rather than one virtual
address.

### Storage

| | Storage |
|---|---|
| Deployment | all replicas share whatever the template names. There is no way to give each replica its own volume |
| DaemonSet | typically a `hostPath`, because the job is to read something on that node — logs, `/proc`, the container runtime socket |
| StatefulSet | `volumeClaimTemplates` generates one PVC **per pod**, named after the pod, and a pod reattaches to its own claim on restart |

Task 9 showed the three claims appearing automatically:

    mysql-persistent-storage-mysql-0   Bound   5Gi
    mysql-persistent-storage-mysql-1   Bound   5Gi
    mysql-persistent-storage-mysql-2   Bound   5Gi

and deleting `mysql-1` brought it back with the same name, on the same node, attached to
the same claim — so the same data. Only the IP changed. Compare with the ReplicaSet,
where the replacement pod had a different name entirely. That difference is the entire
reason StatefulSets exist.

### Summary

| | Deployment | DaemonSet | StatefulSet |
|---|---|---|---|
| Replica count | you choose | one per eligible node | you choose |
| Pod names | random suffix | random suffix | ordinal: `-0`, `-1`, `-2` |
| Start order | parallel | parallel | sequential |
| Stable DNS per pod | no | no | yes, via headless Service |
| Per-pod storage | no | no | yes, `volumeClaimTemplates` |
| Survives rescheduling with identity | no | n/a | yes |
| Example | nginx, an API | node-exporter, Fluentd | MySQL, Kafka |

---

## 3. ReplicaSet vs Service

These are often confused because both are "about" a group of pods, but they do unrelated
jobs and neither can substitute for the other.

### What a ReplicaSet is responsible for

Keeping the right **number** of pods alive. It watches pods matching its selector, counts
them, and creates or deletes to reach the desired count. It knows nothing about traffic,
ports or addresses. A ReplicaSet with three healthy pods that nobody can reach is, as far
as it is concerned, completely successful.

### What a Service is responsible for

Giving those pods a **stable address and a way in**. It does not create, delete, restart
or monitor pods. A Service pointing at zero pods is a perfectly valid object: it has a
ClusterIP, DNS answers for it, and every connection fails.

### Why a Service is required

Because pod IPs are temporary. Task 9 showed a deleted pod being replaced with a new name
and a new IP within seconds, and task 10 showed `mysql-1` coming back on a different
address. Anything holding a pod IP would be wrong almost immediately.

A Service solves this with a fixed ClusterIP and a DNS name that outlive any individual
pod. Clients use the name; the set of pods behind it churns freely.

### How traffic actually reaches a pod

1. A client resolves the Service name through CoreDNS and gets the ClusterIP.
2. It sends a packet there. Nothing is listening on that address — it is not bound to any
   interface on any machine.
3. The **EndpointSlice controller** has been maintaining a list of the ready pods matching
   the Service's selector.
4. `kube-proxy` has programmed packet filter rules on every node from that list.
5. Those rules rewrite the destination to one of the real pod IPs.
6. The packet arrives at a pod.

The ReplicaSet is the reason there are pods in step 3. The Service is steps 1 to 5.

### Where they meet: labels

Neither object references the other. There is no field on a ReplicaSet naming a Service,
and none on a Service naming a ReplicaSet. They are connected only by **pod labels** —
the ReplicaSet stamps labels onto the pods it creates, and the Service selects pods
carrying those labels.

Which is why a one-character typo breaks everything while both objects look healthy. Task
10 demonstrates this deliberately: a Service selecting `app: web-clusterp` against pods
labelled `app: web-clusterip` gives

    $ kubectl get endpoints broken-web-service
    NAME                 ENDPOINTS   AGE
    broken-web-service   <none>      0s

The ReplicaSet is fine, three pods are running and ready. The Service is fine, it has a
ClusterIP and resolves. Nothing is wrong with either object individually, and nothing
works.

### Summary

| | ReplicaSet | Service |
|---|---|---|
| Responsible for | how many pods exist | how pods are reached |
| Creates pods | yes | never |
| Has an IP | no | yes, the ClusterIP (except headless) |
| Cares if a pod dies | yes, replaces it | only removes it from the endpoint list |
| Connected to the other by | pod labels | pod labels |
| Useless without the other | reachable by nothing | points at nothing |
