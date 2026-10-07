#!/usr/bin/env bash
# Generates load against the hpa-demo Service from inside the cluster, so the
# traffic actually reaches the pods rather than going through a port-forward.
#
#   ./load-generator.sh start    launch the load pods
#   ./load-generator.sh stop     remove them
#
# Each pod runs a tight wget loop. One is not enough to move nginx's CPU past
# the 50% target, so several run in parallel.
#
# The target is the Service ClusterIP rather than its DNS name on purpose: six
# loops resolving the name on every single request overwhelmed CoreDNS and the
# generators died with "bad address". Hitting the IP removes DNS from the loop.

set -euo pipefail
WORKERS="${WORKERS:-6}"
TARGET="${TARGET:-http://$(kubectl get svc hpa-demo-service -o jsonpath='{.spec.clusterIP}')}"

case "${1:-start}" in
  start)
    echo "starting $WORKERS load generators against $TARGET"
    for i in $(seq 1 "$WORKERS"); do
      kubectl run "load-gen-$i" --image=busybox:1.36 --restart=Never -- \
        /bin/sh -c "while true; do wget -q -O- $TARGET > /dev/null; done" >/dev/null
    done
    echo "running. watch with:  kubectl get hpa hpa-demo --watch"
    ;;
  stop)
    kubectl delete pod -l run --ignore-not-found >/dev/null 2>&1 || true
    for i in $(seq 1 "$WORKERS"); do
      kubectl delete pod "load-gen-$i" --ignore-not-found >/dev/null 2>&1 || true
    done
    echo "load generators removed"
    ;;
  *)
    echo "usage: $0 [start|stop]" >&2; exit 1 ;;
esac
