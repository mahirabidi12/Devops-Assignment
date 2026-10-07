# FQDN in Kubernetes

Notes for Session 11, Task 3. Everything here was checked against the three node kind
cluster used for the rest of this task, and the captured output appears in the main
`../README.md` alongside the Service work.

## What an FQDN is

FQDN stands for Fully Qualified Domain Name: a name that is complete, so it means the
same thing no matter where it is used from.

The everyday comparison is addressing a letter. Inside one room, "pass it to Rahul" is
enough, because there is only one Rahul and everybody present knows which one. Posting a
letter to him needs the whole address, down to the city and country, because the postal
system has no idea which room you were standing in.

Kubernetes works the same way. A pod talking to a Service in its own namespace can use
the short name. A pod talking across namespaces, or anything outside the cluster, needs
the complete name.

## The anatomy of a Service FQDN

Every Service gets a name of this shape automatically:

    web-service-clusterip  .  default  .  svc  .  cluster.local
    └────────┬───────────┘    └───┬───┘   └─┬─┘   └──────┬─────┘
             │                    │         │            │
       Service name          Namespace   Object type  Cluster domain

| Segment | What it is |
|---|---|
| `web-service-clusterip` | the Service's `metadata.name` |
| `default` | the namespace the Service lives in |
| `svc` | the object type, which is how DNS knows this is a Service and not a pod |
| `cluster.local` | the cluster domain, set when the cluster is built; `cluster.local` is the default |

So the general form is:

    <service>.<namespace>.svc.cluster.local

## Why the short name works: `/etc/resolv.conf`

Kubernetes writes a DNS configuration into every pod it starts. From the client pod used
in this task:

    $ kubectl exec curl-client -- cat /etc/resolv.conf
    search default.svc.cluster.local svc.cluster.local cluster.local
    nameserver 10.96.0.10
    options ndots:5

Three lines, and each one matters:

**`nameserver 10.96.0.10`** is the ClusterIP of the CoreDNS Service. Every lookup the
container makes goes there. Note it is an ordinary ClusterIP, so cluster DNS is itself
reached through the same Service mechanism as everything else.

**`search ...`** is an autocomplete list. Asking for `web-service-clusterip` makes the
resolver try each suffix in order:

1. `web-service-clusterip.default.svc.cluster.local` — match, stop here
2. `web-service-clusterip.svc.cluster.local`
3. `web-service-clusterip.cluster.local`

Because `default.svc.cluster.local` is tried first, a short name resolves to a Service in
the pod's **own** namespace. That is the whole reason short names work, and also the
reason they silently do the wrong thing across namespaces.

**`options ndots:5`** says that any name with fewer than five dots should be tried against
the search list before being treated as a public domain.

## Same namespace versus across namespaces

Both pods in `default`:

    [frontend pod] ── curl http://backend ──► [backend Service]   works

The resolver appends `default.svc.cluster.local` and finds it.

Pods in different namespaces, a test pod in `dev` calling a Service in `production`:

    curl http://backend                                  fails
    curl http://backend.production                       works
    curl http://backend.production.svc.cluster.local     works

The first one fails because the resolver looks for `backend.dev.svc.cluster.local`, which
does not exist. Adding the namespace is the minimum fix; the full FQDN is unambiguous and
is what belongs in configuration files.

## Three kinds of name

**1. Service FQDN** — returns the Service's single virtual ClusterIP:

    <service>.<namespace>.svc.cluster.local

Confirmed on this cluster:

    $ kubectl exec curl-client -- nslookup web-service-clusterip.default.svc.cluster.local
    Name:	web-service-clusterip.default.svc.cluster.local
    Address: 10.96.8.240

**2. StatefulSet pod FQDN through a headless Service** — every replica gets its own
permanent record:

    <pod>.<service>.<namespace>.svc.cluster.local

Confirmed on this cluster:

    $ kubectl exec curl-client -- nslookup web-stateful-0.web-service-headless.default.svc.cluster.local
    Name:	web-stateful-0.web-service-headless.default.svc.cluster.local
    Address: 10.244.1.41

This is what clustered software needs. A Kafka broker or a MySQL replica has to reach one
specific peer, not a randomly chosen one, so `kafka-0` must always mean that exact pod.

**3. Pod IP-based FQDN** — any pod also gets a record derived from its IP, with the dots
replaced by dashes:

    <pod-ip-with-dashes>.<namespace>.pod.cluster.local

A pod at `10.244.2.85` in `default` is `10-244-2-85.default.pod.cluster.local`. Rarely
used directly, since the address is in the name and the name dies with the pod.

## Pod-to-Service communication, end to end

1. The application asks for `web-service-clusterip`.
2. The resolver sees fewer than 5 dots, so it walks the `search` list and asks CoreDNS
   for `web-service-clusterip.default.svc.cluster.local`.
3. CoreDNS answers with the Service's ClusterIP, `10.96.8.240`.
4. The pod sends a packet to that address. Nothing is listening on it anywhere — it is
   not bound to any interface on any machine.
5. `kube-proxy` rules on the node rewrite the destination to one of the real pod IPs from
   the Service's EndpointSlice.
6. The packet reaches a pod.

Steps 1 to 3 are DNS. Steps 4 to 6 are routing. Keeping the two apart is what makes a
broken Service quick to diagnose, and it is the same split used in the Linux networking
task earlier in this homework.

## Examples

| Name | Resolves to |
|---|---|
| `web-service-clusterip` | short name, only from a pod in `default` |
| `web-service-clusterip.default` | works from any namespace |
| `web-service-clusterip.default.svc.cluster.local` | the full FQDN, unambiguous |
| `web-service-headless.default.svc.cluster.local` | every pod IP behind the headless Service |
| `web-stateful-0.web-service-headless.default.svc.cluster.local` | one specific StatefulSet pod |
| `kubernetes.default.svc.cluster.local` | the API server Service |
| `kube-dns.kube-system.svc.cluster.local` | CoreDNS itself |

## Cheat sheet

    Service FQDN        <service>.<namespace>.svc.cluster.local
    StatefulSet pod     <pod>.<service>.<namespace>.svc.cluster.local
    Pod by IP           <ip-with-dashes>.<namespace>.pod.cluster.local
    Same namespace      short name is enough
    Other namespace     at least <service>.<namespace>
    DNS server          CoreDNS, a ClusterIP in kube-system, usually 10.96.0.10
    Diagnostic          nslookup or dig, from inside a pod
