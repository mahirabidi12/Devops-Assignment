# Kubernetes Fundamentals

Notes on the Kubernetes architecture, written up from the official documentation at
https://kubernetes.io/docs/concepts/architecture/, plus the Docker Compose exercise from
the same session.

## What a cluster is

Deploying Kubernetes gives you a **cluster**: a set of worker machines called **nodes**
that run containerised applications, and a **control plane** that manages them. Every
cluster has at least one worker node. The nodes host the **Pods**, which are the units
the application workload actually runs in.

The division of labour is the thing to hold on to. You never tell Kubernetes "start this
container on that machine". You describe the state you want, the control plane works out
how to reach it, and it keeps working to hold the cluster there. That is what
"declarative" means in practice, and it is why a pod that dies comes back without anyone
intervening.

## Control plane components

These make the global decisions, such as scheduling, and react to cluster events like a
Deployment's replica count no longer being satisfied. They can run on any machine, but
setup tools normally place them all on one node and keep user workloads off it.

### kube-apiserver

The front end of the control plane, and the only component that talks to `etcd`.
Everything else, including `kubectl`, reaches the cluster through its REST API. It
authenticates the caller, validates the object being submitted, applies admission
control, and then persists the result. It is stateless, so it scales horizontally by
running more instances behind a load balancer.

The practical consequence: if the API server is down, nothing can be changed and
`kubectl` stops working, but pods already running on the nodes keep serving traffic,
because the kubelet on each node carries on with the spec it already has.

### etcd

A consistent, highly available key-value store, and the only place cluster state lives.
Every object, its spec and its status, is a key in `etcd`. This makes it the one
component that genuinely needs a backup plan; losing it means losing the cluster's
entire definition, even if every node is healthy.

It uses the Raft consensus algorithm, which is why production clusters run an odd number
of members, usually three or five, so a majority can always be established.

### kube-scheduler

Watches for newly created pods that have no node assigned, and picks a node for each one.
The decision accounts for resource requests against available capacity, hardware,
software and policy constraints, affinity and anti-affinity rules, taints and
tolerations, data locality and deadlines.

Worth being precise about what it does: the scheduler only writes the chosen node name
into the pod object. It never starts a container. The kubelet on the named node notices
the pod has been assigned to it and does the actual work.

### kube-controller-manager

Runs the controller processes. Each controller is logically separate, but they are
compiled into one binary and run in a single process to keep things simple. Every one of
them follows the same reconciliation loop: observe the current state, compare it with the
desired state, act to close the gap, repeat forever.

The controllers include:

- **Node controller** — notices when a node stops reporting and responds, which is what
  triggers pods being rescheduled elsewhere.
- **Job controller** — watches Job objects representing one-off tasks and creates pods to
  run them to completion.
- **EndpointSlice controller** — populates EndpointSlice objects, providing the link
  between a Service and the pods behind it.
- **ServiceAccount controller** — creates the default ServiceAccounts for new namespaces.

### cloud-controller-manager

Embeds cloud provider specific logic and runs only the controllers relevant to that
provider, for example creating a real load balancer when a Service of type
`LoadBalancer` is requested, or managing node routes. Separating it out is what keeps the
core components free of provider specific code.

On a local cluster like kind or minikube this component is absent, which is exactly why a
`LoadBalancer` Service stays `<pending>` there — nothing is present to fulfil it.

## Node components

These run on every node, maintaining the running pods and providing the runtime
environment.

### kubelet

The agent on each node. It takes the PodSpecs assigned to its node and makes sure the
containers described in them are running and healthy, reporting status back to the API
server. It also runs the liveness, readiness and startup probes.

One boundary worth knowing: the kubelet only manages containers Kubernetes created. A
container started by hand with `docker run` on the same machine is invisible to it.

### kube-proxy

A network proxy on each node that implements part of the Service concept. It maintains
the network rules that allow traffic to reach pods, from inside or outside the cluster,
using the operating system's packet filtering layer where one is available and forwarding
the traffic itself otherwise.

In practice it programs iptables or IPVS rules so that a connection to a Service's
virtual IP is rewritten to the address of one of the pods behind it. This is also why a
ClusterIP never answers a ping: it is a rule in a packet filter, not an interface on any
machine.

### Container runtime

The software that actually runs containers. Kubernetes supports **containerd**, **CRI-O**
and any other implementation of the **CRI** (Container Runtime Interface). Docker Engine
itself was removed as a directly supported runtime in v1.24, since it did not speak CRI;
containerd, which Docker uses internally anyway, is the common choice now.

## How a pod actually gets created

Tracing one `kubectl apply` through the components above ties them together:

1. `kubectl` sends the object to **kube-apiserver**.
2. The API server authenticates, validates and admits it, then writes it to **etcd**.
3. The **scheduler** sees a pod with no `nodeName`, chooses a node, and patches the object.
4. The **kubelet** on that node sees a pod assigned to it and asks the **container
   runtime** to pull the image and start the containers.
5. The kubelet reports status back through the API server, so `kubectl get pods` shows
   `Running`.
6. **kube-proxy** programs the packet filtering rules if a Service selects the new pod.

Nothing in that chain involves one component calling another directly. Each one watches
the API server and acts on what it sees, which is why the pieces can be restarted
independently.

## Docker Compose exercise

Before moving to Kubernetes, the session covered Docker Compose, which solves the same
problem at single host scale: describing a multi container application in one file rather
than running a series of `docker run` commands by hand.

The stack in `docker-compose/docker-compose.yml` is the three tier setup from the Docker
networking homework, rebuilt declaratively: an Nginx frontend, an Alpine backend and a
MySQL database, on two networks so the frontend has no route to the database.

    services:
      frontend:   nginx:alpine, port 8080:80, bind mounts website/index.html
      backend:    alpine, on both networks
      database:   mysql:8.0, on backend-net only, with a named volume

    networks:  frontend-net, backend-net
    volumes:   db-data

Running it:

    cd docker-compose
    docker compose up -d
    docker compose ps
    curl http://localhost:8080
    docker compose down -v        # -v also removes the named volume

Points worth recording from writing this file:

- `depends_on` with `condition: service_healthy` waits for the database's healthcheck to
  pass, rather than only waiting for the container to be created. Plain `depends_on`
  starts the backend as soon as MySQL's container exists, which is well before MySQL is
  ready to accept a connection.
- The two networks reproduce the isolation from the previous homework. The backend is on
  both, the frontend only on `frontend-net`, so the frontend cannot resolve `database` at
  all. Compose creates these networks with a project name prefix.
- Service names are the hostnames. The backend reaches the database at `database:3306`
  with no addresses written down anywhere, the same name based discovery Docker provides
  on any user defined network.
- `db-data` is a named volume rather than a bind mount, so the database files are managed
  by Docker and survive `docker compose down` unless `-v` is passed.
- The bind mount for `index.html` is `:ro`, since the web server only needs to read it.

### How this maps onto Kubernetes

The comparison is the useful part of doing Compose immediately before Kubernetes:

| Compose | Kubernetes |
|---|---|
| a `service` | a Deployment plus a Service |
| `image:` | the container spec in a pod template |
| `ports: 8080:80` | a Service, of type NodePort or behind an Ingress |
| `networks:` | flat pod network by default, restricted with NetworkPolicy |
| service name as hostname | Service DNS name |
| named `volumes:` | PersistentVolumeClaim |
| `environment:` | env, or a ConfigMap and Secret |
| `deploy.replicas` | `spec.replicas` on a Deployment |
| `docker compose up -d` | `kubectl apply -f` |

The two real differences: Compose runs on one machine while Kubernetes schedules across a
cluster, and Compose runs the file once whereas Kubernetes stores the desired state and
keeps reconciling towards it. That second point is why deleting a pod created by a
Deployment gets you a replacement, while `docker rm` on a Compose container just leaves
it gone.
