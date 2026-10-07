# VPC — Virtual Private Cloud

Session 18, Task 2.4. The network layer every other AWS resource sits inside, and the thing
session 19 builds with Terraform.

## What a VPC is

A logically isolated network inside AWS, with an IP range you choose and complete control
over subnets, routing and firewalls. Nothing in it is reachable from the internet unless
you build a path.

Every account gets a default VPC per region with public subnets and an internet gateway
already wired up. It is convenient and should not be used for anything real — a purpose-built
VPC is the first thing an infrastructure project creates.

A VPC is **regional** and spans every availability zone in that region.

## CIDR

The address range, written as `10.0.0.0/16`. The number after the slash is how many leading
bits are fixed; the rest are available for hosts.

| CIDR | Addresses | Common use |
|---|---|---|
| `/16` | 65,536 | a whole VPC |
| `/24` | 256 | one subnet |
| `/28` | 16 | the smallest AWS allows |

AWS permits `/16` through `/28` for a VPC. Use the private ranges from RFC 1918 —
`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`.

**AWS reserves five addresses in every subnet**: network, VPC router, DNS, future use, and
broadcast. A `/24` gives 251 usable addresses, not 256.

The planning mistake that hurts later is overlapping ranges. Two VPCs that both use
`10.0.0.0/16` can never be peered, and a VPC overlapping the office network breaks the VPN.
Allocate ranges centrally before anyone builds anything.

## Subnets

A slice of the VPC CIDR bound to **one availability zone**. This is the key property:
subnets do not span AZs, so high availability means at least one subnet per AZ.

A subnet is **public** if its route table sends `0.0.0.0/0` to an internet gateway, and
**private** otherwise. There is no flag — it is entirely determined by routing.

The standard three-tier layout, duplicated across two or three AZs:

| Tier | Contains | Internet |
|---|---|---|
| Public | load balancers, NAT gateways | in and out |
| Private app | application servers, containers | out only, via NAT |
| Private data | databases, caches | none |

## Route tables

A set of rules matched **most-specific-prefix-first**. Every subnet is associated with
exactly one route table; the VPC has a main table used by any subnet not explicitly
associated.

A public subnet's table:

    10.0.0.0/16   →  local          (implicit, cannot be removed)
    0.0.0.0/0     →  igw-xxxxx

A private subnet's table:

    10.0.0.0/16   →  local
    0.0.0.0/0     →  nat-xxxxx

The `local` route is what makes everything inside the VPC able to reach everything else by
default. Isolation between tiers comes from security groups, not routing.

## Internet gateway

A horizontally scaled, highly available component attached to the VPC that allows traffic
to and from the internet. One per VPC, and it costs nothing.

It does two things: routes traffic, and performs one-to-one NAT between an instance's
private address and its public or Elastic IP. That is why an instance never sees its own
public address.

Three conditions must all hold for an instance to be internet-reachable: an IGW attached to
the VPC, a `0.0.0.0/0` route to it in the subnet's table, and a public IP on the instance.
Missing any one is the usual reason a new instance is unreachable.

## NAT gateway

Lets instances in **private** subnets reach out to the internet — for package updates,
API calls, pulling container images — while remaining unreachable from it.

Points that matter:

- It lives in a **public** subnet and needs an Elastic IP.
- It is **zonal**, so a NAT gateway in a failed AZ takes that AZ's egress with it. Real
  high availability means one per AZ.
- It is **not free**. An hourly charge plus a per-GB data processing charge, and it is a
  frequent surprise on bills. A NAT gateway costs roughly as much per month as a small
  instance, before data.
- For AWS services, a **VPC endpoint** avoids NAT entirely. An S3 gateway endpoint is free
  and keeps traffic off the internet, which is both cheaper and more secure.

A NAT **instance** is the older, cheaper, self-managed alternative: a single EC2 instance
you have to patch, scale and make redundant yourself.

## Security groups

Covered in the EC2 notes, restated here for contrast: **stateful**, attached to network
interfaces, **allow rules only**, and able to reference other security groups.

## Network ACLs

The subnet-level firewall, and the counterpart that behaves differently in every respect:

| | Security group | Network ACL |
|---|---|---|
| Attached to | an ENI (instance) | a subnet |
| State | **stateful** | **stateless** |
| Rules | allow only | allow **and** deny |
| Evaluation | all rules together | numbered, first match wins |
| Return traffic | automatic | needs its own explicit rule |

Stateless is the part that catches people. Allowing inbound 443 on a NACL is not enough —
the response leaves from an ephemeral port, so an outbound rule for 1024–65535 is also
required.

The default NACL allows everything both ways. In practice security groups do almost all the
work, and NACLs are reserved for coarse subnet-wide denials, such as blocking a hostile IP
range.

## Public vs private subnet

The practical difference, restated because it is the thing to get right:

|  | Public | Private |
|---|---|---|
| Route for `0.0.0.0/0` | internet gateway | NAT gateway, or none |
| Instances get public IPs | optionally | no |
| Reachable from internet | yes | no |
| Can reach internet | yes | through NAT only |
| Put here | load balancers, NAT, bastions | apps, databases, everything else |

The rule of thumb: if it does not need to accept connections from the internet, it belongs
in a private subnet. In a well-built VPC the public subnets contain almost nothing — a load
balancer and a NAT gateway — and all the actual workload is private.

## Common use cases

| Need | Design |
|---|---|
| Standard web application | ALB public, app private, RDS in isolated private subnets, across 2 AZs |
| Reach S3 without NAT | S3 gateway VPC endpoint, free |
| Connect two VPCs | VPC peering for a pair; Transit Gateway beyond that |
| Connect to on-premises | Site-to-Site VPN, or Direct Connect for dedicated bandwidth |
| Audit traffic | VPC Flow Logs to CloudWatch or S3 |

## Relevance to this course

Session 19 builds exactly this: a VPC with a CIDR, a subnet, an internet gateway, a route
table and a security group, with an EC2 instance inside it — then tears it down with
`terraform destroy`. The ordering constraints in that build are real dependencies: the
subnet needs the VPC, the route needs the gateway, the instance needs the subnet and the
security group. Terraform works that graph out from the references, which is the point of
the exercise.
