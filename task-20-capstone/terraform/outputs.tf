output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "Control plane version."
  value       = module.eks.cluster_version
}

output "vpc_id" {
  description = "VPC the cluster runs in."
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "Private subnets holding the worker nodes."
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "Public subnets, for load balancers."
  value       = module.vpc.public_subnets
}

output "configure_kubectl" {
  description = "Run this to point kubectl at the new cluster."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}
