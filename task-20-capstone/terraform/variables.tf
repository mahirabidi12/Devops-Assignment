variable "aws_region" {
  description = "Region to build in."
  type        = string
  default     = "ap-south-1"
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
  default     = "taskboard-eks"
}

variable "owner" {
  description = "Tag applied to every resource, so costs can be attributed."
  type        = string
  default     = "capstone"
}

variable "vpc_cidr" {
  description = "CIDR for the VPC."
  type        = string
  default     = "10.30.0.0/16"
}

variable "kubernetes_version" {
  description = "EKS control plane version."
  type        = string
  default     = "1.31"
}

variable "node_instance_type" {
  description = "Worker instance type. t3.medium is the smallest that comfortably runs the EKS system pods plus this application."
  type        = string
  default     = "t3.medium"
}

variable "node_desired_size" {
  description = "Worker count. Two gives the scheduler somewhere to move pods during a rollout."
  type        = number
  default     = 2
}

variable "single_nat_gateway" {
  description = "One NAT gateway for all AZs rather than one each. Cheaper, but a single point of failure - acceptable for a teaching build, not for production."
  type        = bool
  default     = true
}
