variable "aws_region" {
  description = "Region to build the infrastructure in."
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Prefix for every resource name, so they are identifiable and easy to clean up."
  type        = string
  default     = "scaler-devops"
}

variable "vpc_cidr" {
  description = "CIDR for the VPC. A /16 leaves room for many subnets."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR block."
  }
}

variable "public_subnet_cidr" {
  description = "CIDR for the public subnet. Must sit inside vpc_cidr."
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR for the private subnet."
  type        = string
  default     = "10.0.2.0/24"
}

variable "instance_type" {
  description = "EC2 instance type. t3.micro is free-tier eligible in most regions."
  type        = string
  default     = "t3.micro"
}

variable "allowed_ssh_cidr" {
  description = "CIDR permitted to reach port 22. Deliberately not 0.0.0.0/0 - set it to your own address."
  type        = string
  default     = "10.0.0.0/16"
}
