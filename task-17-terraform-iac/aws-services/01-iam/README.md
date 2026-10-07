# IAM — Identity and Access Management

Session 18, Task 2.1. AWS's governance layer: who can do what, to which resources, under
which conditions.

## What IAM is

IAM controls authentication (who are you) and authorisation (what may you do) for every
AWS API call. It is global, not regional, and free.

Every request to AWS is signed and evaluated against policy before anything happens. There
is no implicit trust: an EC2 instance cannot read an S3 bucket in the same account unless
something explicitly allows it.

## Users

An IAM user is a long-lived identity for a person or an application, with its own
credentials — a console password, access keys, or both.

Users are the part of IAM you should use least. Access keys do not expire, get committed to
git, end up in CI configuration, and are the single most common cause of AWS account
compromise. Modern practice is human access through IAM Identity Center with short-lived
credentials, and workload access through roles.

## Groups

A collection of users, with policies attached to the group rather than each user.

Groups hold **users only** — you cannot nest a group inside a group, and you cannot attach
a group to a role or a service. They exist purely to stop you attaching the same policy to
forty people individually.

A typical layout: `developers`, `read-only`, `billing`, `admins`.

## Roles

An identity with permissions that is **assumed temporarily** rather than logged into. A
role has no password and no access keys. Something assumes it and receives credentials that
expire, typically in an hour.

This is the mechanism that matters most, and it covers:

- **EC2 instance profiles** — an instance assumes a role and gets credentials from the
  instance metadata service. No keys on disk.
- **Service roles** — Lambda, ECS tasks, EKS pods via IRSA, all assume roles.
- **Cross-account access** — a role in account A trusts a principal in account B.
- **Federation** — an identity provider (Okta, Google, GitHub Actions via OIDC) exchanges
  its token for a role.

Every role has two policies, and conflating them is a common source of confusion:

| Policy | Answers |
|---|---|
| **Trust policy** | *who may assume this role* |
| **Permissions policy** | *what the role may do once assumed* |

## Policies

JSON documents listing permissions. Evaluation is: **explicit deny > explicit allow >
implicit deny**. Everything is denied unless allowed, and any deny anywhere wins.

    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Sid": "ReadOneBucket",
          "Effect": "Allow",
          "Action": ["s3:GetObject", "s3:ListBucket"],
          "Resource": [
            "arn:aws:s3:::my-app-bucket",
            "arn:aws:s3:::my-app-bucket/*"
          ],
          "Condition": {
            "IpAddress": {"aws:SourceIp": "203.0.113.0/24"}
          }
        }
      ]
    }

Note the two ARNs. `ListBucket` acts on the bucket itself; `GetObject` acts on the objects
inside it. Granting one without the other is a frequent mistake.

Policy types:

| Type | Attached to | Notes |
|---|---|---|
| AWS managed | users, groups, roles | written by AWS, e.g. `ReadOnlyAccess`; convenient, usually too broad |
| Customer managed | users, groups, roles | your own, reusable, versioned — the one to prefer |
| Inline | a single identity | embedded, deleted with it; use only for genuinely one-off grants |
| Resource-based | the resource | e.g. an S3 bucket policy; can grant cross-account without a role |
| Permissions boundary | a user or role | a ceiling that caps what any attached policy can grant |
| SCP | an Organizations OU | an account-wide ceiling, cannot grant anything |

## Permissions

A permission is the `Action` plus `Resource` plus optional `Condition`. Actions are
namespaced by service: `s3:GetObject`, `ec2:RunInstances`, `iam:PassRole`.

`iam:PassRole` deserves special mention. It controls whether a principal may hand a role to
a service — launching an EC2 instance with an admin instance profile, for example. A user
with `ec2:RunInstances` and unrestricted `iam:PassRole` is effectively an administrator,
because they can launch an instance holding any role in the account. It is the standard
privilege-escalation path and should always be scoped to specific role ARNs.

## Least privilege

Grant only the permissions actually required, and no more.

In practice:

- Start from nothing and add what breaks, rather than starting from `*` and trimming.
- Scope `Resource` to specific ARNs. `"Resource": "*"` is rarely correct.
- Use conditions — source IP, MFA present, requested region, resource tag.
- Use IAM Access Analyzer to generate a policy from CloudTrail history of what an identity
  actually called.
- Review and remove unused permissions; IAM reports last-used data per service.

## Best practices

1. Lock away the root user. MFA on it, no access keys, use it only for the handful of tasks
   that require it.
2. MFA for every human.
3. Roles for workloads, never access keys on an instance or in a container.
4. Federate human access rather than creating IAM users.
5. Rotate any long-lived key that must exist, and audit with the credential report.
6. Permissions boundaries so that a developer who can create roles cannot create one more
   powerful than themselves.
7. SCPs at the organisation level for guardrails that no account admin can override.
8. CloudTrail on in every region, logging to a bucket in a separate account.
9. Tag identities and use `aws:ResourceTag` conditions for attribute-based access control.
10. Never hardcode credentials. The SDK credential chain finds roles automatically.

## Common use cases

| Need | Mechanism |
|---|---|
| EC2 reads from S3 | instance profile with a scoped role |
| CI/CD deploys to AWS | GitHub Actions OIDC federation into a deploy role |
| Pod in EKS calls AWS | IRSA — a service account annotated with a role ARN |
| Vendor needs access | cross-account role with an external ID |
| Developers need read-only prod | group with `ReadOnlyAccess`, MFA condition |
| Prevent region sprawl | SCP denying all regions except the approved ones |

## Relevance to the rest of this course

The Terraform work in this session and the next authenticates as an IAM principal, and
every resource it creates is permitted or denied by IAM. The credentials used should be a
scoped role rather than a long-lived admin key — the same least-privilege argument applies
to automation more strongly than to people, because automation runs unattended.
