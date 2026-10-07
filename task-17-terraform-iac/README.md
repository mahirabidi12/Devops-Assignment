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

## All eight commands were run against live AWS

`init`, `fmt`, `validate`, `plan`, `apply`, `show`, `output` and `destroy` all executed in
`ap-south-1`. The bucket `scaler-devops-demo-49ac66c3` was created, inspected, and
destroyed in the same sitting.

    Apply complete!   Resources: 8 added, 0 changed, 0 destroyed.
    Plan:             0 to add, 0 to change, 8 to destroy.

Full transcripts and what each step shows are in
[`terraform-s3-demo/README.md`](terraform-s3-demo/README.md).

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
| `screenshots/18-03-apply.png` | the apply, with parallel creation and the 57s lifecycle rule |
| `screenshots/18-04-show-output.png` | `output`, `output -raw` and `show` |
| `screenshots/18-05-destroy.png` | the destroy plan and the confirmation |

## Cleanup

Already done — `terraform destroy` removed all 8 resources straight after the
demonstration, so nothing is left billing.
