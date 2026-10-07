output "bucket_name" {
  description = "Name of the created bucket, including the random suffix."
  value       = aws_s3_bucket.demo.id
}

output "bucket_arn" {
  description = "ARN of the bucket, for use in IAM and bucket policies."
  value       = aws_s3_bucket.demo.arn
}

output "bucket_region" {
  description = "Region the bucket lives in. Buckets are regional even though the namespace is global."
  value       = aws_s3_bucket.demo.region
}

output "versioning_status" {
  description = "Whether object versioning is enabled."
  value       = aws_s3_bucket_versioning.demo.versioning_configuration[0].status
}
