# Terraform & Infrastructure as Code

Session 18. Two tasks: a Terraform project that provisions an S3 bucket, and research
write-ups on five AWS services.

| Folder | Task | Covers |
|---|---|---|
| [`terraform-s3-demo/`](terraform-s3-demo/README.md) | Task 1 | an S3 bucket in Terraform, with the full command workflow |
| [`aws-services/01-iam/`](aws-services/01-iam/README.md) | Task 2.1 | users, groups, roles, policies, least privilege |
| [`aws-services/02-ec2/`](aws-services/02-ec2/README.md) | Task 2.2 | AMIs, instance types, key pairs, security groups, EBS, lifecycle |
| [`aws-services/03-s3/`](aws-services/03-s3/README.md) | Task 2.3 | buckets, objects, storage classes, versioning, lifecycle, encryption |
| [`aws-services/04-vpc/`](aws-services/04-vpc/README.md) | Task 2.4 | CIDR, subnets, route tables, gateways, security groups, NACLs |
| [`aws-services/05-dynamodb-rds/`](aws-services/05-dynamodb-rds/README.md) | Task 2.5 | DynamoDB and RDS, and choosing between them |

## Important: planned, not applied

`terraform init`, `fmt`, `validate` and `plan` were all run for real against a live AWS
account. **`apply` was not run.**

`plan` is read-only and free. `apply` creates billable resources, which is the account
owner's decision rather than something to do unattended. The exact commands and expected
output for `apply`, `show`, `output` and `destroy` are documented in
[`terraform-s3-demo/README.md`](terraform-s3-demo/README.md).

An empty S3 bucket costs essentially nothing, so this is a cheap one to actually apply —
unlike the EC2 instance in [session 19](../task-18-cloud-terraform/README.md).

## What the Terraform creates

Eight resources, because a bucket's settings are separate resources in the AWS provider:
the bucket itself, a random name suffix, versioning, encryption, public access block,
ownership controls, a lifecycle configuration and a bucket policy denying non-TLS requests.

    Plan: 8 to add, 0 to change, 0 to destroy.

## The AWS research notes

Written as reference material rather than summaries, each covering the points the homework
lists plus the failure modes that actually bite:

- **IAM** — why `iam:PassRole` is the standard privilege-escalation path, and why roles beat
  access keys for every workload.
- **EC2** — burstable `t` instances throttling to baseline when credits run out, and why an
  instance never sees its own public IP.
- **S3** — minimum storage durations making IA cost *more* for short-lived objects, and
  versioning without a lifecycle rule growing forever.
- **VPC** — the five reserved addresses per subnet, and NAT gateways being zonal and billed
  hourly.
- **DynamoDB & RDS** — Multi-AZ being availability not scale, and the hot-partition problem
  from a low-cardinality partition key.

## Screenshots

| File | Shows |
|---|---|
| `screenshots/18-01-init-validate.png` | `init`, `fmt -check`, `validate` |
| `screenshots/18-02-plan.png` | the 8 planned resources and the plan summary |

## Cleanup

Nothing was created, so there is nothing to clean up. If you do run `apply`, run
`terraform destroy` immediately afterwards.
