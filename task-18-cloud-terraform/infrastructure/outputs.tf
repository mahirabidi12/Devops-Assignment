output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR range of the VPC."
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_id" {
  description = "Public subnet, the one with a route to the internet gateway."
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "Private subnet, no route to the internet."
  value       = aws_subnet.private.id
}

output "web_security_group_id" {
  description = "Security group applied to the web instance."
  value       = aws_security_group.web.id
}

output "instance_public_ip" {
  description = "Public IP of the web instance. Changes on stop/start - use an Elastic IP or a load balancer for anything stable."
  value       = aws_instance.web.public_ip
}

output "instance_private_ip" {
  description = "Private IP, stable for the life of the instance."
  value       = aws_instance.web.private_ip
}

output "web_url" {
  description = "URL serving the nginx page installed by user_data."
  value       = "http://${aws_instance.web.public_ip}"
}

output "s3_bucket_name" {
  description = "Name of the assets bucket."
  value       = aws_s3_bucket.assets.id
}

output "ami_id" {
  description = "AMI the instance was launched from, resolved by the data source."
  value       = data.aws_ami.amazon_linux.id
}
