# DynamoDB and RDS — Database Services

Session 18, Task 2.5. AWS's two main managed database families, and when each one fits.

---

# DynamoDB

## What it is

A fully managed NoSQL key-value and document database. No servers, no version upgrades, no
storage to provision. Single-digit millisecond latency at effectively any scale, because it
partitions data across machines automatically.

The trade is that you must design the table around your access patterns up front. It will
not rescue a query you did not plan for.

## Tables, items and attributes

| DynamoDB | Relational equivalent |
|---|---|
| table | table |
| item | row |
| attribute | column |

The difference that matters: items in a table need not share a schema. Only the key
attributes are required; everything else varies per item. An item is capped at 400 KB.

## Primary key

Two forms, and the choice shapes everything:

**Partition key alone** — the key hashes to a partition. Lookups are by exact key only.

**Partition key + sort key** (composite) — items sharing a partition key are stored
together, sorted. This enables range queries: "all orders for customer 42 since January",
"the last 10 events for device X".

The partition key must spread load evenly. A key with few distinct values, or one hot value,
creates a hot partition that throttles while the rest of the table idles. Low-cardinality
keys like `status` or `country` are the classic mistake.

## Indexes

| | Local Secondary Index | Global Secondary Index |
|---|---|---|
| Partition key | same as table | any attribute |
| Sort key | different | any attribute |
| Created | only at table creation | any time |
| Capacity | shared with the table | its own |
| Consistency | strong reads available | eventually consistent only |

GSIs are how you support a second access pattern, and each one is a full projected copy of
the data — so they cost storage and write capacity on every write.

## Capacity modes

**On-demand** — pay per request, scales instantly, no planning. Right for spiky or unknown
traffic, and the sane default.

**Provisioned** — you set read and write capacity units, optionally with autoscaling.
Cheaper for steady, predictable load. Exceeding capacity causes throttling, which the SDK
retries with backoff.

## Consistency

Reads are **eventually consistent** by default — a read immediately after a write may return
the old value, because it may be served by a replica that has not caught up. Strongly
consistent reads are available, cost twice as much, and do not work on GSIs.

Writes are always strongly consistent.

## Other features worth knowing

- **TTL** — an attribute holding an expiry timestamp; DynamoDB deletes expired items free.
  Ideal for sessions and caches.
- **Streams** — an ordered log of changes, consumable by Lambda. The basis for event-driven
  patterns and cross-region replication.
- **Global tables** — multi-region active-active replication.
- **Transactions** — all-or-nothing across up to 100 items.
- **PartiQL** — SQL-like syntax, but it does not change the underlying access patterns; a
  query without a usable key still scans.

Scans read the entire table and should be treated as a bug in production code.

---

# RDS — Relational Database Service

## What it is

Managed relational databases. AWS handles provisioning, patching, backups, failover and
replication; you keep SQL, joins, transactions and constraints.

Engines: PostgreSQL, MySQL, MariaDB, Oracle, SQL Server, and **Aurora** — AWS's own
PostgreSQL- and MySQL-compatible engine with a distributed storage layer, faster failover
and storage that grows automatically.

## Instance classes and storage

Sized like EC2 (`db.t3.micro`, `db.m5.large`, `db.r6g.xlarge`), with the same burstable
caveat on the `t` family.

Storage is EBS: `gp3` general purpose, `io1`/`io2` provisioned IOPS. Enable storage
autoscaling — running out of disk takes the database down, and the fix is not instant.

## Multi-AZ

A synchronous standby replica in a second availability zone. It serves **no traffic** — it
exists purely for failover, which is automatic and takes 60–120 seconds, with the endpoint
DNS repointed to the standby.

This is availability, not scale. The common misunderstanding is expecting Multi-AZ to spread
read load; it does not.

## Read replicas

Asynchronous copies that **do** serve reads. Up to 15, can live in other regions, and can be
promoted to standalone primaries.

Because replication is asynchronous there is replica lag, so a read straight after a write
may miss it — the same consistency problem as DynamoDB's eventual reads, arrived at from the
opposite direction.

| | Multi-AZ | Read replica |
|---|---|---|
| Replication | synchronous | asynchronous |
| Serves reads | no | yes |
| Purpose | availability | scaling reads |
| Failover | automatic | manual promotion |

## Backups

**Automated backups** — daily snapshot plus transaction logs, giving point-in-time recovery
to any second in the retention window (up to 35 days). Deleted with the instance unless a
final snapshot is taken.

**Manual snapshots** — kept until explicitly deleted, and shareable between accounts.

Restoring always creates a **new instance** with a new endpoint. There is no in-place
restore, which has to be planned for in any recovery runbook.

## Security

- Put RDS in **private subnets**. A publicly accessible database is almost never correct.
- A DB subnet group spanning at least two AZs is required for Multi-AZ.
- Security group allowing the database port **from the application security group only**,
  never a CIDR.
- Encryption at rest with KMS — can only be enabled **at creation**; adding it later means
  snapshot, copy with encryption, restore.
- **IAM database authentication** issues short-lived tokens instead of passwords.
- **Secrets Manager** for credentials, with automatic rotation.

That last pair connects directly to the Kubernetes Secrets work in task 11: a password in a
Secret is base64, not encrypted, and still ends up in the pod's environment in plaintext.
IAM auth removes the long-lived password from the system entirely, which is the stronger fix.

---

## Choosing between them

| Use DynamoDB when | Use RDS when |
|---|---|
| access patterns are known and few | queries are ad hoc or evolving |
| scale is very large or very spiky | scale is moderate and predictable |
| key-value or document shaped | relational, with joins across entities |
| millisecond latency at any size matters | transactions and constraints matter |
| no operational overhead wanted | the team knows SQL and wants it |

A rough rule: if you would struggle to list every query the application will ever make,
use a relational database. DynamoDB rewards certainty and punishes change.

Most real systems use both — RDS for core business entities, DynamoDB for sessions, feature
flags, event logs and anything needing extreme write throughput.

## Relevance to this course

The capstone project in session 21 specifies PostgreSQL with Alembic migrations, which is
RDS territory. The Terraform work in sessions 18 and 19 provisions the VPC and subnets that
such a database would sit in — specifically the isolated private tier described in the VPC
notes.
