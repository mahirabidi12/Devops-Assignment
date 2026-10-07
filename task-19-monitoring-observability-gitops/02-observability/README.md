# Observability

Session 20, Task 2. The three pillars, and the distinction from monitoring.

## Monitoring vs observability

They are not the same thing, and the difference is practical rather than semantic.

| | Monitoring | Observability |
|---|---|---|
| Answers | is the thing I expected to break, broken? | why is it behaving like this? |
| Needs | the failure modes known in advance | enough data to ask new questions |
| Shape | dashboards and alerts on known metrics | querying high-cardinality data after the fact |
| Fails when | something breaks in a way nobody predicted | — |

Monitoring is a subset. You monitor what you already know to watch — CPU, memory, error
rate, the alerts in `../01-monitoring/alerts.yml`. Observability is the property of a system
that lets you answer questions you did not think to ask before the incident started.

The usual test: can you work out why *one particular customer's* request was slow at 14:32,
without deploying new code? Dashboards cannot answer that. That is the gap observability
fills.

## Pillar 1 — Metrics

Numbers over time, aggregated. Cheap to store, cheap to query, fixed shape.

Demonstrated for real in [`../01-monitoring/`](../01-monitoring/README.md), where
Prometheus scraped node-exporter and the CPU and memory figures were derived from counters
and gauges.

The four metric types:

| Type | Behaviour | Example |
|---|---|---|
| Counter | only increases, resets to 0 on restart | `node_cpu_seconds_total`, requests served |
| Gauge | up and down | memory in use, queue depth, replica count |
| Histogram | bucketed observations | request duration, with quantiles computed at query time |
| Summary | quantiles computed in the client | request duration, pre-aggregated |

**Metrics are aggregate by nature, and that is their limitation.** `http_requests_total` can
tell you the error rate rose, never which request failed or why. Every label you add
multiplies the series count, so adding `user_id` as a label would create one series per user
and destroy the database. This cardinality ceiling is exactly why the other two pillars
exist.

## Pillar 2 — Logs

Discrete events with full context. Expensive to store, searchable, arbitrary detail.

    2026-10-07T20:14:02Z ERROR  order-service  order_id=A-7731 user_id=4192
      payment gateway timeout after 30s  trace_id=8f3a2b1c

A log line carries what a metric cannot — the specific order, the specific user, the error
text. That is what makes it the right tool once a metric has told you *that* something is
wrong.

**Structured beats unstructured.** JSON logs with consistent fields can be queried;
free-text prose can only be grepped. `level=error service=order order_id=A-7731` is useful
in a way that `Something went wrong processing the order` is not.

In Kubernetes, `kubectl logs` reads from the node's disk. It is enough for one pod being
debugged right now, and useless at any scale — as seen repeatedly in
[task 13](../../task-13-kubernetes-troubleshooting/01-commands/README.md), where logs for a
crashed container needed `--previous` and were gone entirely once the pod was replaced.
Shipping logs off the node with Fluent Bit or Promtail into Loki or Elasticsearch is what
makes them survive.

## Pillar 3 — Traces

The path of one request through every service it touched, with timing at each hop.

    trace 8f3a2b1c
    ├─ api-gateway        12ms
    ├─ auth-service        8ms
    ├─ order-service     412ms   ◀── the time is here
    │   ├─ postgres        9ms
    │   └─ payment-api   398ms   ◀── and specifically here
    └─ notification        5ms

This is the pillar that answers "why was it slow", and nothing else does. The metric says
p99 latency is 450ms. The log says a timeout happened. The trace says *which of the seven
services* consumed the time, in one view.

Tracing needs **context propagation** — a trace ID generated at the edge and passed through
every call, usually in the W3C `traceparent` header. That is the real cost of adopting
tracing: every service has to pass it along, and any service that drops it breaks the chain
from that point on.

OpenTelemetry is the vendor-neutral standard for all three signals, and is now the default
choice for instrumentation.

## How they work together

The pillars are a workflow, not a menu:

1. **A metric alerts.** Error rate crossed its threshold. You know *that* something is wrong
   and roughly when.
2. **A trace localises it.** Among the services in the request path, one is consuming the
   time or returning the errors. You know *where*.
3. **A log explains it.** The error text, the stack trace, the specific record. You know
   *why*.

Metrics for detection, traces for localisation, logs for explanation. Teams that skip
tracing tend to do step 2 by guesswork and reading code, which is where most of the time in
an incident goes.

## Application health

What to instrument, in order of value:

**RED, for request-driven services** — Rate, Errors, Duration.

**USE, for resources** — Utilisation, Saturation, Errors. Saturation is the one people miss:
a CPU at 100% is less alarming than a run queue that keeps growing.

**The four golden signals** — latency, traffic, errors, saturation.

And in Kubernetes specifically, the probes from
[task 9's pod lifecycle](../../task-9-kubernetes-pods-replicasets-deployments/pod-lifecycle/README.md)
are health signals the platform acts on rather than merely reports. A readiness probe is not
a dashboard — it removes the pod from the Service. That is the difference between
observability and control.

## Practical notes

**Alert on symptoms, not causes.** "Error rate above 2%" is actionable. "CPU above 80%" is
often fine, and paging on it trains people to ignore pages.

**Every alert needs a runbook.** An alert nobody knows how to action is noise with a
pager attached.

**Cardinality is the budget.** Labels multiply. One metric with a `user_id` label on a
service with a million users is a million series.

**Sample traces, keep all logs for errors.** Tracing every request is expensive; tail-based
sampling keeps the slow and failed ones, which are the ones worth having.
