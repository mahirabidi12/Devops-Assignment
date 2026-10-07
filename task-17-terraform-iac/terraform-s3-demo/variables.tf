variable "aws_region" {
  description = "AWS region to create the bucket in."
  type        = string
  default     = "ap-south-1"
}

variable "bucket_name_prefix" {
  description = "Prefix for the bucket name. A random suffix is appended because S3 bucket names are globally unique across every AWS account."
  type        = string
  default     = "scaler-devops-demo"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.bucket_name_prefix))
    error_message = "Bucket name prefix must be lowercase letters, digits and hyphens only."
  }
}

variable "environment" {
  description = "Environment name, applied as a tag."
  type        = string
  default     = "dev"
}

variable "enable_versioning" {
  description = "Whether to keep every version of an object. Protects against accidental deletion and overwrite."
  type        = bool
  default     = true
}

variable "noncurrent_version_expiration_days" {
  description = "How long to keep superseded object versions. Versioning without this grows forever and is a common source of surprise S3 bills."
  type        = number
  default     = 30
}
