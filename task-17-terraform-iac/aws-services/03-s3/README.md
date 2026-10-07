# S3 — Simple Storage Service

Session 18, Task 2.3. Object storage, and the service the Terraform demo in this task
provisions.

## What S3 is

S3 stores objects — files with metadata — addressed by key, retrieved over HTTP. It is not
a filesystem: there is no append, no partial write, no rename. You PUT a whole object and
GET a whole object.

Durability is 99.999999999% (eleven nines) by replicating across at least three
availability zones. Capacity is effectively unlimited and you pay only for what you store,
request and transfer out.

## Buckets

The top-level container. A bucket lives in **one region** and its name is **globally
unique across all AWS accounts** — which is why every tutorial bucket name is already
taken, and why Terraform examples append a random suffix or the account ID.

Naming rules worth knowing: 3–63 characters, lowercase, no underscores, not formatted like
an IP address. Dots are legal but break TLS wildcard certificates for virtual-hosted-style
access, so avoid them.

Buckets are private by default, and since 2023 **Block Public Access** is on by default at
the account level. Making a bucket public now takes several deliberate steps, which is a
direct response to years of accidental data exposure.

## Objects

Each object has a key, a value up to 5 TB, metadata, and a version ID if versioning is on.

The key is a flat string. S3 has **no directories** — `logs/2026/10/07/app.log` is one key
containing slashes. The console renders a folder tree by splitting on `/`, but nothing
hierarchical exists underneath. This matters when deleting: there is no "delete folder",
only "delete every key with this prefix".

Anything above 100 MB should use multipart upload, which splits the object into parts that
upload in parallel and retry individually. Abandoned multipart uploads keep costing money
invisibly until a lifecycle rule cleans them up.

## Storage classes

| Class | For | Retrieval |
|---|---|---|
| Standard | frequent access | immediate |
| Intelligent-Tiering | unknown or changing patterns | immediate, tiers automatically |
| Standard-IA | infrequent, needs to be fast | immediate, cheaper storage, per-GB retrieval fee |
| One Zone-IA | infrequent, reproducible | immediate, single AZ, 20% cheaper |
| Glacier Instant Retrieval | archive, occasional immediate access | milliseconds |
| Glacier Flexible Retrieval | archive | minutes to hours |
| Glacier Deep Archive | compliance, rarely touched | up to 12 hours |

The trap in the IA and Glacier classes is the **minimum storage duration** — 30 days for IA,
90 for Glacier Flexible, 180 for Deep Archive. Delete sooner and you are charged for the
remainder anyway. Lifecycle rules that move small, short-lived objects to IA can cost more
than leaving them in Standard.

Intelligent-Tiering is the safe default when access patterns are genuinely unknown: a small
monitoring fee per object, and AWS moves things between tiers for you with no retrieval
charges.

## Versioning

Keeps every version of an object under the same key. Once enabled on a bucket it can be
suspended but **never disabled**.

With versioning on, a delete does not remove anything — it writes a zero-byte **delete
marker** as the newest version. The object disappears from listings but every prior version
is still stored and still billed. Recovering is a matter of deleting the marker.

That is excellent protection against accidental deletion and against ransomware, and it is
also a silent cost: a bucket with versioning and no lifecycle policy grows forever. The two
features belong together.

MFA Delete goes further, requiring an MFA token to delete a version or change versioning
state. It can only be configured by the account root user, which makes it awkward enough
that it is reserved for genuinely critical buckets.

## Lifecycle policies

Rules that transition or expire objects automatically based on age or prefix.

    logs/   →  Standard-IA after 30 days
            →  Glacier after 90 days
            →  deleted after 365 days

    noncurrent versions  →  deleted after 30 days
    incomplete multipart uploads  →  aborted after 7 days

The last two are the ones people forget, and they are exactly where unexplained S3 bills
come from.

## Encryption

**At rest**, every bucket is encrypted by default now (SSE-S3). The options:

| Option | Key held by | Use when |
|---|---|---|
| SSE-S3 | AWS, fully managed | default, no requirements |
| SSE-KMS | AWS KMS, your key | you need an audit trail and key policies |
| SSE-C | you supply it per request | you must hold the keys yourself |
| Client-side | you, before upload | AWS must never see plaintext |

SSE-KMS is the common choice for anything sensitive because every decrypt is a KMS API call
recorded in CloudTrail, so you can see who read what. It costs more and is subject to KMS
request limits — enable S3 Bucket Keys to cut both substantially.

**In transit**, use TLS, and enforce it with a bucket policy denying requests where
`aws:SecureTransport` is false.

## Bucket policies

A resource-based policy attached to the bucket. Unlike an IAM policy, it can grant access
to principals in other accounts without a role.

    {
      "Version": "2012-10-17",
      "Statement": [{
        "Sid": "DenyUnencryptedTransport",
        "Effect": "Deny",
        "Principal": "*",
        "Action": "s3:*",
        "Resource": ["arn:aws:s3:::my-bucket", "arn:aws:s3:::my-bucket/*"],
        "Condition": {"Bool": {"aws:SecureTransport": "false"}}
      }]
    }

Access is the union of IAM policies, the bucket policy, ACLs and Block Public Access — and
an explicit `Deny` anywhere wins. Block Public Access overrides everything, which is the
point of it.

ACLs are the legacy mechanism and AWS now recommends disabling them entirely by setting
object ownership to `BucketOwnerEnforced`.

## Common use cases

| Need | How |
|---|---|
| Static website | S3 + CloudFront with an Origin Access Control; the bucket stays private |
| Application uploads | presigned URLs so clients upload directly, never through your server |
| Backups | versioning, lifecycle to Glacier, Object Lock for immutability |
| Data lake | Parquet partitioned by prefix, queried with Athena |
| Terraform state | a bucket with versioning plus DynamoDB for state locking |
| Log archive | CloudTrail and ALB logs delivered to a dedicated bucket |

The Terraform state use case is the relevant one here: the local `terraform.tfstate` used
in this session is fine for one person, but a team needs remote state in S3 with a DynamoDB
lock table so two people cannot apply at once.

## What the demo in this task creates

`terraform-s3-demo/` provisions a single bucket with versioning enabled, public access
blocked and server-side encryption on — the minimum a bucket should have before anything is
put in it.
