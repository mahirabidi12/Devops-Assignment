# EC2 — Elastic Compute Cloud

Session 18, Task 2.2. Virtual machines in AWS.

## What EC2 is

EC2 rents virtual servers by the second. You choose an image, a size and a network, and get
a machine you have full control over — and full responsibility for.

It sits at the bottom of the compute abstraction ladder: most flexible, most work. Above it
are ECS and EKS (you manage containers, AWS manages the scheduler), then Fargate (no
servers to manage), then Lambda (no servers at all). Choosing EC2 should be a decision, not
a default.

## AMI — Amazon Machine Image

The template an instance boots from: operating system, pre-installed software, and
configuration baked into a snapshot.

AMIs are **regional**. An AMI ID in `ap-south-1` is meaningless in `us-east-1`, which is a
common cause of Terraform code that works in one region and fails in another. The fix is to
look the AMI up with a data source filtered by name and owner rather than hardcoding an ID.

Sources: AWS-provided (Amazon Linux, Ubuntu), Marketplace (vendor images, sometimes with
hourly fees), and your own — built with Packer in a CI pipeline so that deployments launch a
pre-baked image rather than running configuration at boot. That "golden AMI" pattern is
immutable infrastructure applied to VMs.

## Instance types

Named `family.generation.size` — `t3.micro`, `m5.large`, `c6g.xlarge`. The families:

| Family | Optimised for | Typical use |
|---|---|---|
| `t` | burstable | dev boxes, low-traffic sites |
| `m` | general purpose | balanced app servers |
| `c` | compute | batch processing, encoding, game servers |
| `r`, `x` | memory | in-memory caches, large databases |
| `i`, `d` | storage | NoSQL stores, data warehouses |
| `p`, `g`, `inf` | accelerated | ML training and inference |

The `t` family is worth understanding because it surprises people. Burstable instances earn
CPU credits while idle and spend them under load. Exhaust the credits and the instance is
throttled to its baseline — sometimes 5 or 10 percent of a core. A `t3.micro` that is fine
for a week can collapse under sustained load. `unlimited` mode removes the ceiling and
charges for the excess.

A `g` suffix (`c6g`) means Graviton, AWS's ARM processors — cheaper per unit of work, but
the image and every binary must be ARM-compatible. This is the same architecture question
that broke `mysql:5.7` on the Apple Silicon machine back in task 9.

## Key pairs

An SSH public/private key pair. AWS stores the public key and injects it into the instance
at launch; you keep the private key. **AWS never stores the private key**, so losing it
means losing SSH access to that instance — recovery means detaching the root volume and
attaching it to another instance.

Better practice is to avoid SSH entirely. **AWS Systems Manager Session Manager** gives
shell access through the SSM agent with no open port 22, no key management, and full
CloudTrail audit of who connected. An instance with a Session Manager role and no inbound
SSH rule is both more secure and easier to operate.

## Security groups

A stateful virtual firewall attached to an instance's network interface.

- **Stateful**: allow an inbound request and the response is automatically allowed out. You
  do not write return rules.
- **Allow-only**: there is no deny rule. Anything not explicitly allowed is denied.
- **Default**: all outbound allowed, no inbound allowed.
- Rules can reference **another security group** rather than a CIDR — "allow 5432 from the
  app tier security group" keeps working as instances come and go.

That last point is the one worth internalising. Referencing security groups instead of IP
ranges is how you express tiers, and it is the same idea as a Kubernetes Service selecting
pods by label rather than by address.

`0.0.0.0/0` on port 22 or 3389 is the classic mistake, and bots find it within minutes.

## EBS — Elastic Block Store

Network-attached block storage that persists independently of the instance.

| Type | Character |
|---|---|
| `gp3` | general purpose SSD, IOPS configured separately from size — the sane default |
| `gp2` | older SSD, IOPS tied to volume size |
| `io2` | provisioned IOPS, for demanding databases |
| `st1`, `sc1` | throughput and cold HDD, for sequential bulk data |

Key properties: EBS volumes live in **one availability zone** and can only attach to an
instance in that zone. They can be snapshotted to S3, and snapshots are regional, which is
how you move a volume between zones. Encryption at rest is a checkbox and should always be
on.

The important distinction is against **instance store** — physical disks on the host, very
fast, and **wiped when the instance stops**. Fine for scratch and caches, catastrophic for
anything else.

Note the parallel with Kubernetes: instance store is `emptyDir`, EBS is a PersistentVolume.
Same distinction, same consequences.

## Public vs private IP

| | Private IP | Public IP | Elastic IP |
|---|---|---|---|
| Reachable from | inside the VPC | the internet | the internet |
| Survives a stop/start | yes | **no** | yes |
| Cost | free | free while attached | charged when *not* attached |

The instance itself never sees its public IP. The OS is configured with the private address
only, and the internet gateway performs the translation — which is why `ifconfig` inside an
EC2 instance shows a `10.x` address and confuses people.

A public IP changes on stop/start. Anything depending on a stable address needs an Elastic
IP, or better, a load balancer or DNS name in front.

## Instance lifecycle

    pending → running → stopping → stopped → terminated
                    ↘ rebooting ↗

| Transition | What happens |
|---|---|
| stop → start | moves to a new physical host; public IP changes; instance store lost; EBS kept |
| reboot | same host; nothing lost; IP unchanged |
| terminate | gone permanently; root volume deleted unless the delete-on-termination flag was cleared |
| hibernate | RAM written to the root EBS volume and restored on start |

Billing stops in `stopped` for compute, but EBS volumes are still charged. A fleet of
stopped instances with large volumes is a real and common bill.

Purchase options: On-Demand (flexible, most expensive), Reserved and Savings Plans (commit
one or three years for a large discount), and **Spot** (spare capacity at up to 90 percent
off, reclaimed with a two-minute warning). Spot is excellent for stateless, interruptible
work — CI runners, batch jobs, Kubernetes worker nodes behind a well-configured autoscaler.

## Common use cases

| Need | Approach |
|---|---|
| Traditional web app | EC2 in private subnets behind an Application Load Balancer, in an Auto Scaling Group |
| Legacy software needing a real OS | a single instance with an Elastic IP and tight security groups |
| Batch or CI | Spot instances in an Auto Scaling Group |
| Kubernetes workers | EC2 managed node groups in EKS |
| Bastion host | ideally none at all — Session Manager instead |

## Relevance to this course

Session 19 builds a VPC, subnet, security group and EC2 instance with Terraform. Everything
above shows up there: choosing the AMI with a data source rather than a literal ID, putting
the instance in the right subnet, and writing a security group that does not open SSH to
the world.
