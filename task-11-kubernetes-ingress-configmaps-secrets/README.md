# Kubernetes Ingress, ConfigMaps & Secrets

Configuration and HTTP routing, run against a real three node kind cluster with the
`ingress-nginx` controller installed. Manifests are in `manifests/`.

## 1. Ingress vs Ingress Controller

This distinction is the one most worth being precise about, because the two names sound
like the same thing and are not.

- **Ingress** is a Kubernetes API object. It holds routing rules: which host and which
  path should reach which Service. On its own it is inert, a piece of configuration
  sitting in `etcd`.
- **Ingress Controller** is software actually running in the cluster, such as NGINX,
  Traefik or HAProxy, that watches Ingress objects and implements them. It is the thing
  that terminates the connection and proxies the request.

Without a controller, an Ingress object does nothing at all. Applying one on a bare
cluster produces no error and no effect, which is a confusing first experience. Proof
from this cluster, before installing anything:

    $ kubectl get ingressclass
    No resources found

Installing the controller is a separate step:

    $ kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
    $ kubectl get pods -n ingress-nginx
    NAME                                        READY   STATUS    RESTARTS   AGE
    ingress-nginx-controller-596f5b6bcf-stn4z   1/1     Running   0          55s

    $ kubectl get ingressclass
    NAME    CONTROLLER             PARAMETERS   AGE
    nginx   k8s.io/ingress-nginx   <none>       55s

`ingressClassName: nginx` in the manifests is what binds an Ingress to this controller.
A cluster can run several controllers at once, and the class is how each object says
which one owns it.

### Why Ingress rather than a LoadBalancer per service

From the previous task: every `LoadBalancer` Service asks the cloud provider for its own
load balancer, and each one is separately billed. An Ingress inverts that. One load
balancer fronts the controller, and the controller fans out to any number of Services
based on host and path. Ten public endpoints then cost one load balancer instead of ten,
and TLS is terminated in one place.

## 2. Path-based vs Host-based routing

- **Host-based** routes on the `Host` header, so on the domain requested.
  `portal.campus.local` goes to one Service, `api.campus.local` to another.
- **Path-based** routes on the URL path under one domain. `example.com/api` goes to one
  Service, `example.com/` to another.

They compose freely, and `manifests/03-ingress/ingress-tls.yaml` uses both: two hosts,
with a path rule inside one of them.

### Both, demonstrated

`manifests/04-full-demo/` deploys an nginx frontend and a small Python backend that
prints its own configuration, with `yatri-ingress` routing between them.

    $ kubectl get ingress
    NAME            CLASS   HOSTS         ADDRESS     PORTS   AGE
    yatri-ingress   nginx   yatri.local   localhost   80      61s

Path `/` reaches the frontend:

    $ curl -s -H "Host: yatri.local" http://localhost/
    <!DOCTYPE html>
    <html>
    <head>
    <title>Welcome to nginx!</title>
    ...
    <h1>Welcome to nginx!</h1>

Path `/api` reaches the backend:

    $ curl -s -H "Host: yatri.local" http://localhost/api
    Yatri Backend API
    =================
    ENVIRONMENT     : production
    LOG_LEVEL       : INFO
    DEFAULT_CURRENCY: INR
    POSTGRES_USER   : yatri_admin
    POSTGRES_DB     : yatri_production_db

Same host, same port, two different Services, chosen purely on path.

And the host rule is genuinely enforced:

    $ curl -s -o /dev/null -w "%{http_code}\n" -H "Host: wrong.local" http://localhost/
    404

The request reached the controller and was rejected, because no rule matches that host.
The `Host` header is being used for routing, not the address, which is why `curl` needs
`-H "Host: ..."` throughout rather than a real DNS entry.

### A real problem hit while setting this up

The first attempt returned nothing at all, not even an error:

    $ curl -s -o /dev/null -w "%{http_code}\n" -H "Host: yatri.local" http://localhost/
    000

`000` from curl means the connection never completed, so this was not an Ingress rule
problem. The cause:

    $ kubectl get pods -n ingress-nginx -o wide
    ingress-nginx-controller-596f5b6bcf-stn4z   devops-worker

    $ docker port devops-control-plane
    80/tcp -> 0.0.0.0:80
    443/tcp -> 0.0.0.0:443

The kind cluster forwards host ports 80 and 443 to the **control plane** node, but the
controller pod had been scheduled onto `devops-worker`, where nothing is forwarded. The
controller uses `hostPort: 80`, so it only works on a node whose port 80 is actually
mapped through.

kind's documented setup labels the intended node `ingress-ready=true` and the controller
manifest selects it. The label was present, but the current upstream manifest no longer
carries that selector:

    $ kubectl get deploy -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.template.spec.nodeSelector}'
    {"kubernetes.io/os":"linux"}

So the pod was free to land anywhere. Pinning it back:

    $ kubectl patch deployment -n ingress-nginx ingress-nginx-controller --type=merge \
        -p '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/os":"linux","ingress-ready":"true"}}}}}'

    $ kubectl get pods -n ingress-nginx -o wide
    ingress-nginx-controller-575c4d8bc6-5nsr6   Running   devops-control-plane

After which every request above worked. Worth recording because the failure mode is
misleading: nothing in `kubectl get ingress` or `describe` looks wrong, and the Ingress
rules were correct the whole time. The distinction between `000` (never connected) and
`404` (connected, no rule matched) is what localises the fault.

## 3. ConfigMaps

A ConfigMap holds non-confidential configuration as key-value pairs, so that settings
live outside the image. The same image can then run in dev and production with different
behaviour.

    $ kubectl apply -f manifests/01-configmap/
    configmap/yatri-app-config created

    $ kubectl get configmap yatri-app-config
    NAME               DATA   AGE
    yatri-app-config   5      0s

    $ kubectl get configmap yatri-app-config -o go-template='{{range $k,$v := .data}}{{$k}} = {{$v}}{{"\n"}}{{end}}'
    DEFAULT_CURRENCY = INR
    ENVIRONMENT = production
    LOG_LEVEL = INFO
    MAX_BOOKING_DAYS = 30
    PORT = 5000

The backend consumes the whole map at once with `envFrom`:

    envFrom:
      - configMapRef:
          name: yatri-app-config

which is why `curl /api` printed `ENVIRONMENT: production` and `LOG_LEVEL: INFO` above.
Individual keys can also be selected with `valueFrom.configMapKeyRef`, or the map can be
mounted as a volume, where each key becomes a file.

### The gotcha: updating a ConfigMap does not update running pods

    $ kubectl patch configmap yatri-app-config --type=merge -p '{"data":{"LOG_LEVEL":"DEBUG"}}'
    $ kubectl get configmap yatri-app-config -o jsonpath='{.data.LOG_LEVEL}'
    DEBUG

    $ curl -s -H "Host: yatri.local" http://localhost/api | grep LOG_LEVEL
    LOG_LEVEL       : INFO

The ConfigMap says `DEBUG` and the application still reports `INFO`. Environment
variables are resolved once, when the container starts; changing the source afterwards
cannot reach into a running process.

    $ kubectl rollout restart deployment/yatri-backend
    deployment "yatri-backend" successfully rolled out

    $ curl -s -H "Host: yatri.local" http://localhost/api | grep LOG_LEVEL
    LOG_LEVEL       : DEBUG

Only after a restart. This is a standard source of confusion, and the two ways around it
are to mount the ConfigMap as a volume instead, where the kubelet does refresh the files
after a delay and an application that re-reads them picks changes up, or to make config
changes always trigger a rollout, commonly by hashing the config into a pod annotation.

## 4. Secrets

A Secret is the same shape as a ConfigMap but intended for sensitive values, and it is
handled a little more carefully: values are not printed by `describe`, and the kubelet
keeps them in memory rather than writing them to disk on the node.

    $ kubectl get secret yatri-db-secret
    NAME              TYPE     DATA   AGE
    yatri-db-secret   Opaque   3      0s

    $ kubectl describe secret yatri-db-secret
    Type:  Opaque

    Data
    ====
    POSTGRES_DB:        19 bytes
    POSTGRES_PASSWORD:  14 bytes
    POSTGRES_USER:      11 bytes

Key names and sizes, no values.

### Base64 is encoding, not encryption

The single most important thing to understand about Secrets:

    $ kubectl get secret yatri-db-secret -o jsonpath='{.data.POSTGRES_PASSWORD}'
    c2VjcmV0cGFzc3dvcmQ=

    $ kubectl get secret yatri-db-secret -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d
    secretpassword

Anyone who can read the Secret can read the password, because base64 is reversible by
design and needs no key. The encoding exists so binary data can sit in YAML, not to
protect anything. Real protection comes from RBAC restricting who may read Secrets,
enabling encryption at rest for `etcd`, and keeping the plaintext out of git in the first
place, typically with Sealed Secrets, SOPS or an external vault.

The practical corollary: a Secret manifest with real credentials must never be committed.
The values in `manifests/02-secret/db-secret.yaml` are deliberately throwaway teaching
values.

### The trailing newline bug, reproduced

A classic failure is a password that is provably correct and still rejected, because
`echo` appends a newline:

    $ echo "mypassword" | xxd | tail -1
    00000000: 6d79 7061 7373 776f 7264 0a              mypassword.

That final `0a` is the newline. Encoding it carries the newline through:

    $ echo "mypassword" | base64
    bXlwYXNzd29yZAo=

    $ echo -n "mypassword" | base64
    bXlwYXNzd29yZA==

The application receives `mypassword\n`, 11 characters, and the database correctly
refuses it. `-n` suppresses the newline. The tell is visible in the encoded string
itself: a value ending `Ao=` usually means a trailing newline was captured, whereas the
correct one here ends `==`.

`kubectl create secret generic --from-literal=` avoids the whole problem by doing the
encoding itself.

## 5. TLS Ingress

`manifests/03-ingress/ingress-tls.yaml` terminates HTTPS for two hosts, with the
certificate supplied by a Secret of type `kubernetes.io/tls`.

    $ openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout tls.key -out tls.crt \
        -subj "/CN=portal.campus.local" \
        -addext "subjectAltName=DNS:portal.campus.local,DNS:api.campus.local"

    $ kubectl create secret tls campus-tls-cert --cert=tls.crt --key=tls.key
    secret/campus-tls-cert created

    $ kubectl apply -f manifests/03-ingress/ingress-tls.yaml
    ingress.networking.k8s.io/campus-ingress-tls created

    $ kubectl get ingress
    NAME                 CLASS   HOSTS                                  PORTS     AGE
    campus-ingress-tls   nginx   portal.campus.local,api.campus.local   80, 443   9s
    yatri-ingress        nginx   yatri.local                            80        5m1s

`PORTS` now lists 443 as well, which appears because the `tls:` block is present.

### HTTPS working, on both hosts

    $ curl -sk --resolve portal.campus.local:443:127.0.0.1 -o /dev/null -w "%{http_code}\n" https://portal.campus.local/
    200

    $ curl -sk --resolve api.campus.local:443:127.0.0.1 https://api.campus.local/api
    Yatri Backend API
    =================
    ENVIRONMENT     : production
    LOG_LEVEL       : INFO
    DEFAULT_CURRENCY: INR
    POSTGRES_USER   : yatri_admin
    POSTGRES_DB     : yatri_production_db

Two hosts on one certificate and one controller, each reaching a different Service. `-k`
is needed because the certificate is self-signed, and `--resolve` points the hostname at
localhost without editing `/etc/hosts`.

### The certificate actually being served

    $ echo | openssl s_client -connect localhost:443 -servername portal.campus.local \
        | openssl x509 -noout -subject -ext subjectAltName
    subject=CN=portal.campus.local
    X509v3 Subject Alternative Name:
        DNS:portal.campus.local, DNS:api.campus.local

This confirms the controller loaded the certificate out of the Secret. `-servername` is
SNI, which is how one IP and port serve different certificates per hostname.

### HTTP redirected to HTTPS

    $ curl -s -o /dev/null -w "%{http_code}\n" -H "Host: portal.campus.local" http://localhost/
    308

`308 Permanent Redirect`, produced by the `nginx.ingress.kubernetes.io/ssl-redirect: "true"`
annotation on this Ingress. The other Ingress sets it to `"false"`, which is why plain
HTTP worked for `yatri.local` earlier. 308 rather than 301 because it guarantees the
method and body are preserved, so a redirected POST stays a POST.

## Summary

| Object | Holds | Visible in describe | Typical use |
|---|---|---|---|
| ConfigMap | plain config | yes | env vars, config files, feature flags |
| Secret | sensitive values | no, sizes only | credentials, tokens, TLS certificates |
| Ingress | HTTP routing rules | yes | host and path routing, TLS termination |
| Ingress Controller | the proxy itself | it is a Deployment | implements every Ingress object |

Points worth carrying forward:

- An Ingress without a controller silently does nothing.
- `ingressClassName` is what connects the two.
- Base64 in a Secret is encoding, not protection.
- ConfigMap changes need a pod restart when consumed as environment variables.
- One Ingress can replace many `LoadBalancer` Services, and terminate TLS centrally.
- With `hostPort` based controllers, which node the controller runs on matters.

## Cleanup

    kubectl delete -f manifests/04-full-demo/
    kubectl delete -f manifests/03-ingress/
    kubectl delete -f manifests/01-configmap/ -f manifests/02-secret/
    kubectl delete secret campus-tls-cert
    kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
    kind delete cluster --name devops
