# End-to-end AWS infrastructure: VPC, subnets, internet gateway, route tables,
# security groups, an EC2 instance and an S3 bucket.
#
# Terraform derives the creation order from the references below. Nothing here
# declares "build the VPC first" - the subnet refers to aws_vpc.main.id, so the
# dependency is implied and the graph sorts it out.

# Look the AMI up rather than hardcoding an ID. AMI IDs are regional, so a
# literal would break the moment aws_region changes.
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-6.1-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Availability zones, read from the provider rather than hardcoded.
data "aws_availability_zones" "available" {
  state = "available"
}

# ------------------------------------------------------------------ VPC ----

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  # Both are needed for instances to get DNS names and to resolve them.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# -------------------------------------------------------------- subnets ----

# Public: has a route to the internet gateway, so instances here are reachable.
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public"
    Tier = "public"
  }
}

# Private: no route to the internet gateway. Nothing here is reachable from
# outside, and without a NAT gateway it cannot reach out either. A NAT gateway
# is deliberately omitted - it bills hourly and this is a teaching build.
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "${var.project_name}-private"
    Tier = "private"
  }
}

# ---------------------------------------------------- internet gateway ----

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# --------------------------------------------------------- route tables ----

# What makes the public subnet public: a default route to the IGW.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# The private table has no 0.0.0.0/0 route at all. Only the implicit local
# route for traffic inside the VPC.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# ------------------------------------------------------ security groups ----

resource "aws_security_group" "web" {
  name        = "${var.project_name}-web-sg"
  description = "HTTP from anywhere, SSH from an allowed range only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Not 0.0.0.0/0. An open port 22 is found by scanners within minutes, and
  # Session Manager is the better answer anyway - no inbound rule at all.
  ingress {
    description = "SSH from the allowed range"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-web-sg"
  }
}

# Database tier: reachable only from the web tier, by security group reference
# rather than by CIDR. The rule keeps working as instances come and go, which a
# hardcoded address range would not.
resource "aws_security_group" "database" {
  name        = "${var.project_name}-db-sg"
  description = "PostgreSQL from the web tier only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from the web security group"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-db-sg"
  }
}

# ------------------------------------------------------------------ EC2 ----

resource "aws_instance" "web" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]

  # Encrypt the root volume. It is a checkbox and there is no reason not to.
  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 8
  }

  # Require IMDSv2. IMDSv1 is the mechanism behind several well-known
  # credential-theft incidents via SSRF.
  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 1
  }

  user_data = <<-EOF
    #!/bin/bash
    dnf install -y nginx
    echo "<h1>${var.project_name}</h1><p>Provisioned with Terraform</p>" \
      > /usr/share/nginx/html/index.html
    systemctl enable --now nginx
  EOF

  tags = {
    Name = "${var.project_name}-web"
  }
}

# ------------------------------------------------------------------- S3 ----

resource "aws_s3_bucket" "assets" {
  bucket = "${var.project_name}-assets-${data.aws_caller_identity.current.account_id}"
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket = aws_s3_bucket.assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# A gateway endpoint lets instances reach S3 without going through a NAT
# gateway or the internet. It is free, and it is the standard way to avoid the
# NAT data-processing charge for S3 traffic.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id, aws_route_table.public.id]

  tags = {
    Name = "${var.project_name}-s3-endpoint"
  }
}
