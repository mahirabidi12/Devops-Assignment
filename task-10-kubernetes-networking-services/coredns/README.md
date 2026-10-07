# CoreDNS

Notes for Session 11, Task 4. The command output below was taken from the three node kind
cluster used throughout this task.

## What CoreDNS is

CoreDNS is the DNS server that Kubernetes runs inside the cluster. It is a plain DNS
server written in Go, deployed as an ordinary Deployment in the `kube-system` namespace
and fronted by an ordinary ClusterIP Service called `kube-dns`.

The useful mental picture is a hotel switchboard. Guests do not know which room anyone is
in, and the room changes when people move. They ask the operator for a name and get put
through. CoreDNS is that operator for the cluster: pods ask for a Service name and get an
address back, without anyone writing addresses down.

## Why Kubernetes needs it

Pods are disposable. Every time one is replaced it gets a new IP, as the ReplicaSet
section of task 9 showed — delete a pod and the replacement comes back with a different
address. Hard-coding pod IPs is therefore impossible, and even Service ClusterIPs are
assigned at creation time rather than chosen by you.

So the cluster needs a layer of indirection that maps stable names to current addresses,
and something has to keep that mapping current as pods come and go. That is CoreDNS. It
watches the Kubernetes API and updates its answers as Services and EndpointSlices change,
with no manual step.

## Where it lives

    $ kubectl get deployment coredns -n kube-system
    $ kubectl get pods -n kube-system -l k8s-app=kube-dns
    $ kubectl get svc kube-dns -n kube-system

Two replicas by default, for availability. The Service in front of them is what pods find
at `10.96.0.10` in their `/etc/resolv.conf`.

Note the naming: the Deployment is `coredns` but the Service is still `kube-dns`. The name
was kept when CoreDNS replaced the older kube-dns implementation, so that nothing
depending on the Service name had to change.

## How Service discovery works

1. You create a Service. The API server assigns it a ClusterIP.
2. The EndpointSlice controller finds the pods matching the Service's selector and writes
   their addresses into an EndpointSlice.
3. CoreDNS, watching the API, creates DNS records for the Service.
4. A pod looks the name up and gets an address.

What gets returned depends on the Service type:

| Service type | What DNS returns |
|---|---|
| ClusterIP | one A record, the virtual IP |
| NodePort | the same, a ClusterIP underneath |
| LoadBalancer | the same, a ClusterIP underneath |
| Headless (`clusterIP: None`) | one A record per ready pod |
| ExternalName | a CNAME to the external name, no A record at all |

The headless and ExternalName rows are the interesting ones, and both were verified in
the main README for this task.

## How a query is resolved, step by step

Starting from an application that asks for `web-service-clusterip`:

1. The pod's resolver reads `/etc/resolv.conf`. It sees `ndots:5` and a name with no
   dots, so it treats it as partial and walks the search list.
2. First attempt: `web-service-clusterip.default.svc.cluster.local`, sent to `10.96.0.10`.
3. CoreDNS matches the `cluster.local` zone, recognises `svc`, looks up the Service in
   its cache of the API state, and answers with the ClusterIP.
4. The resolver returns that address and the application connects to it.

If the name had not matched the cluster domain — `github.com`, say — CoreDNS would have
forwarded it to the upstream nameservers from the node's own resolver configuration
instead, and returned whatever came back.

Verified on this cluster:

    $ kubectl exec curl-client -- nslookup web-service-clusterip.default.svc.cluster.local
    Server:		10.96.0.10
    Address:	10.96.0.10:53
    Name:	web-service-clusterip.default.svc.cluster.local
    Address: 10.96.8.240

The `Server` line confirms the answer came from CoreDNS rather than from anywhere else.

## Configuration

CoreDNS is configured by a file called the Corefile, held in a ConfigMap:

    $ kubectl get configmap coredns -n kube-system -o yaml

A default Corefile looks roughly like this:

    .:53 {
        errors
        health
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
           fallthrough in-addr.arpa ip6.arpa
        }
        prometheus :9153
        forward . /etc/resolv.conf
        cache 30
        loop
        reload
        loadbalance
    }

The plugins that matter for understanding it:

| Plugin | What it does |
|---|---|
| `kubernetes` | serves the `cluster.local` zone from the Kubernetes API — this is the whole Service discovery feature |
| `forward . /etc/resolv.conf` | anything not in the cluster zone goes upstream, to the node's own DNS servers |
| `cache 30` | caches answers for 30 seconds, which is why a just-created Service can take a moment to resolve |
| `loop` | detects a forwarding loop and kills the process deliberately rather than hanging |
| `reload` | picks up Corefile edits without a restart |
| `errors`, `health`, `ready` | logging and the probe endpoints |
| `prometheus :9153` | metrics, which matters for the monitoring session later in the course |

Because it is a ConfigMap, changing DNS behaviour cluster-wide means editing it and
waiting for `reload`. A common real edit is adding a stub zone so that one internal
domain is sent to a corporate DNS server instead of the public one.

## Troubleshooting DNS

The first move is always to separate a DNS failure from a routing failure. If the name
resolves but the connection fails, DNS is fine and the problem is the Service or the
pods behind it.

    # 1. is CoreDNS even running
    kubectl get pods -n kube-system -l k8s-app=kube-dns

    # 2. does the pod have sane DNS config
    kubectl exec <pod> -- cat /etc/resolv.conf

    # 3. does the name resolve at all
    kubectl exec <pod> -- nslookup <service>.<namespace>.svc.cluster.local

    # 4. if the FQDN resolves but the short name does not, it is the search list
    kubectl exec <pod> -- nslookup <service>

    # 5. if DNS is fine, the problem is below it
    kubectl get endpointslice -l kubernetes.io/service-name=<service>

    # 6. CoreDNS's own view
    kubectl logs -n kube-system -l k8s-app=kube-dns

### Three failures worth recognising

**A pod in one namespace cannot reach a Service in another.** Almost always a short name
in the configuration. `DB_HOST=mysql` from a pod in `staging` resolves as
`mysql.staging.svc.cluster.local` and fails. Fix the config to `mysql.prod` or the full
FQDN.

**External lookups are slow.** `ndots:5` means a name like `api.stripe.com`, with two
dots, is tried against every search suffix first — three failed queries before the real
one succeeds. On a high-traffic service that latency is measurable. Fix by writing the
name with a trailing dot, `api.stripe.com.`, which marks it already qualified, or by
lowering `ndots` in the pod's `dnsConfig`.

**CoreDNS itself in CrashLoopBackOff.** Usually a forwarding loop. If the node's
`/etc/resolv.conf` points at a local stub resolver such as `127.0.0.53`, CoreDNS inherits
that as its upstream, forwards an unknown query to localhost, and reaches itself. The
`loop` plugin spots this and exits on purpose rather than spinning. Fix by pointing the
kubelet at the real resolver file, or by setting an explicit upstream such as `8.8.8.8`
in the Corefile.

### An empty result that is not DNS at all

Worth repeating because it is the most common confusion: if `nslookup` returns an address
but connections still fail, stop looking at DNS. A Service with a selector matching no
pods still resolves perfectly — it has a ClusterIP and DNS answers for it — while every
connection is refused because there is nothing to forward to. That case is demonstrated
for real in the main README under "The same failure, produced on purpose".
