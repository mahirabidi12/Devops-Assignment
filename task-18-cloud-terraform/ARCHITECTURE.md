# Architecture

## Diagram

    ┌─────────────────────────────────────────────────────────────────────────┐
    │  AWS Region: ap-south-1                                                 │
    │                                                                         │
    │  ┌───────────────────────────────────────────────────────────────────┐  │
    │  │  VPC  scaler-devops-vpc          10.0.0.0/16                      │  │
    │  │  enable_dns_support = true   enable_dns_hostnames = true          │  │
    │  │                                                                   │  │
    │  │   ┌─────────────────────────┐     ┌─────────────────────────┐     │  │
    │  │   │ PUBLIC SUBNET           │     │ PRIVATE SUBNET          │     │  │
    │  │   │ 10.0.1.0/24   AZ-a      │     │ 10.0.2.0/24   AZ-b      │     │  │
    │  │   │                         │     │                         │     │  │
    │  │   │  ┌───────────────────┐  │     │   (no instances here;   │     │  │
    │  │   │  │ EC2  t3.micro     │  │     │    this is where a      │     │  │
    │  │   │  │ Amazon Linux 2023 │  │     │    database would go)   │     │  │
    │  │   │  │ nginx via         │  │     │                         │     │  │
    │  │   │  │   user_data       │  │     │  sg: db-sg              │     │  │
    │  │   │  │ gp3 encrypted     │  │     │  5432 from web-sg only  │     │  │
    │  │   │  │ IMDSv2 required   │  │     │                         │     │  │
    │  │   │  │ sg: web-sg        │  │     │                         │     │  │
    │  │   │  │  :80 from 0.0.0.0 │  │     │                         │     │  │
    │  │   │  │  :22 from allowed │  │     │                         │     │  │
    │  │   │  └───────────────────┘  │     │                         │     │  │
    │  │   └───────────┬─────────────┘     └───────────┬─────────────┘     │  │
    │  │               │                               │                   │  │
    │  │       ┌───────┴────────┐              ┌───────┴────────┐          │  │
    │  │       │ public-rt      │              │ private-rt     │          │  │
    │  │       │ 10.0.0.0/16    │              │ 10.0.0.0/16    │          │  │
    │  │       │   -> local     │              │   -> local     │          │  │
    │  │       │ 0.0.0.0/0      │              │ (no default    │          │  │
    │  │       │   -> igw       │              │  route)        │          │  │
    │  │       └───────┬────────┘              └────────────────┘          │  │
    │  │               │                                                   │  │
    │  │       ┌───────┴────────┐          ┌──────────────────────┐        │  │
    │  │       │ Internet       │          │ S3 Gateway Endpoint  │        │  │
    │  │       │ Gateway        │          │ (both route tables)  │        │  │
    │  │       └───────┬────────┘          └──────────┬───────────┘        │  │
    │  └───────────────┼──────────────────────────────┼────────────────────┘  │
    │                  │                              │                       │
    │                  │                   ┌──────────┴───────────┐           │
    │                  │                   │ S3  assets bucket    │           │
    │                  │                   │ versioned, encrypted │           │
    │                  │                   │ public access blocked│           │
    │                  │                   └──────────────────────┘           │
    └──────────────────┼──────────────────────────────────────────────────────┘
                       │
                   Internet

## Resource list

16 resources, in dependency order:

| # | Resource | Depends on |
|---|---|---|
| 1 | `aws_vpc.main` | — |
| 2 | `aws_internet_gateway.main` | VPC |
| 3 | `aws_subnet.public` | VPC |
| 4 | `aws_subnet.private` | VPC |
| 5 | `aws_route_table.public` | VPC, IGW |
| 6 | `aws_route_table.private` | VPC |
| 7 | `aws_route_table_association.public` | public subnet, public RT |
| 8 | `aws_route_table_association.private` | private subnet, private RT |
| 9 | `aws_security_group.web` | VPC |
| 10 | `aws_security_group.database` | VPC, **web SG** |
| 11 | `aws_instance.web` | public subnet, web SG, AMI data source |
| 12 | `aws_s3_bucket.assets` | caller identity data source |
| 13 | `aws_s3_bucket_versioning.assets` | bucket |
| 14 | `aws_s3_bucket_public_access_block.assets` | bucket |
| 15 | `aws_s3_bucket_server_side_encryption_configuration.assets` | bucket |
| 16 | `aws_vpc_endpoint.s3` | VPC, both route tables |

Not one of these orderings is declared. Terraform reads the references —
`aws_subnet.public` contains `vpc_id = aws_vpc.main.id`, so the VPC must exist first — and
builds the graph itself. That is the whole idea of the tool, and it is why resource 10 waits
for resource 9: the database security group references the web one.

A machine-readable version of the same graph is in `screenshots/dependency-graph.dot`,
produced by `terraform graph`.

## Design decisions

**The AMI is looked up, not hardcoded.** AMI IDs are regional, so a literal would break the
moment `aws_region` changes. A `data "aws_ami"` filtered by name pattern and owner resolves
the current Amazon Linux 2023 image wherever it runs.

**Availability zones come from a data source too.** `data.aws_availability_zones.available`,
indexed `[0]` and `[1]`, so the two subnets land in different zones in any region. Subnets
are zonal, so this is what makes the design survive a zone failure.

**The private subnet has no NAT gateway.** A NAT gateway bills hourly plus per GB and is a
common surprise on a bill. For a teaching build the private subnet demonstrates the routing
difference without the cost. A production design would add one per AZ.

**The database security group references the web security group, not a CIDR.**

    ingress {
      from_port       = 5432
      security_groups = [aws_security_group.web.id]
    }

That rule keeps working as instances come and go. A CIDR-based rule would have to be
rewritten every time the address range changed, and would grant access to anything that
happened to land in the range.

**SSH is not open to the world.** `allowed_ssh_cidr` defaults to the VPC range, and the
example tfvars says to set it to a single address. An open port 22 is found by scanners
within minutes. Session Manager, which needs no inbound rule at all, is the better answer
again.

**IMDSv2 is required.** `http_tokens = "required"` on the instance. IMDSv1 is the mechanism
behind several well-known credential-theft incidents via SSRF — an attacker who can make the
application fetch a URL can read the instance role's credentials. IMDSv2 requires a PUT with
a token first, which an SSRF cannot do.

**The root volume is encrypted.** It is a boolean and there is no reason to leave it off.

**There is an S3 gateway endpoint.** It costs nothing, keeps S3 traffic off the public
internet, and avoids the NAT data-processing charge for anything in the private subnet
talking to S3.

## What this would need to be production-ready

- A second public and private subnet pair in a third AZ
- NAT gateways, one per AZ
- An Application Load Balancer in the public subnets, with the instances moved to private
- An Auto Scaling Group instead of a single instance
- RDS in dedicated isolated subnets using the database security group
- Remote state in S3 with DynamoDB locking
- VPC Flow Logs
