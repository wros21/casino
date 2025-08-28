# VPCs y Peering
output "main_vpc_id" {
  description = "ID de la VPC principal"
  value       = aws_vpc.main.id
}

output "data_vpc_id" {
  description = "ID de la VPC de datos"
  value       = aws_vpc.data.id
}

output "vpc_peering_connection_id" {
  description = "ID del VPC Peering"
  value       = aws_vpc_peering_connection.main_to_data.id
}

# Subnets
output "public_subnet_ids" {
  description = "IDs subredes públicas"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs subredes privadas"
  value       = aws_subnet.private[*].id
}

output "database_subnet_ids" {
  description = "IDs subredes de base de datos"
  value       = aws_subnet.database_subnets[*].id
}

# IGW/NAT
output "internet_gateway_id" {
  description = "ID del Internet Gateway"
  value       = aws_internet_gateway.igw.id
}

output "nat_gateway_id" {
  description = "ID del NAT Gateway"
  value       = aws_nat_gateway.nat.id
}

output "elastic_ip" {
  description = "IP pública del NAT"
  value       = aws_eip.nat.public_ip
}

# ALB / TG
output "load_balancer_dns" {
  description = "DNS del ALB"
  value       = aws_lb.main.dns_name
}

output "load_balancer_zone_id" {
  description = "Hosted Zone ID del ALB"
  value       = aws_lb.main.zone_id
}

output "front_target_group_arn" {
  description = "ARN del Target Group front"
  value       = aws_lb_target_group.front.arn
}

# ASG / LT
output "front_launch_template_id" {
  description = "ID del Launch Template front"
  value       = aws_launch_template.front.id
}

output "front_autoscaling_group_name" {
  description = "Nombre del ASG front"
  value       = aws_autoscaling_group.front.name
}

# RDS
output "rds_endpoint" {
  description = "Endpoint RDS"
  value       = aws_db_instance.data_warehouse.endpoint
  sensitive   = true
}

output "rds_instance_id" {
  description = "ID de la instancia RDS"
  value       = aws_db_instance.data_warehouse.id
}

output "database_name" {
  description = "Nombre de la base de datos"
  value       = aws_db_instance.data_warehouse.db_name
}

# Redis
output "redis_cluster_id" {
  description = "ID del cluster Redis"
  value       = aws_elasticache_cluster.redis.cluster_id
}

output "redis_endpoint" {
  description = "Endpoint Redis"
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
  sensitive   = true
}

output "redis_port" {
  description = "Puerto Redis"
  value       = aws_elasticache_cluster.redis.cache_nodes[0].port
}

# S3 / CloudFront
output "s3_bucket_name" {
  description = "Nombre del bucket S3"
  value       = aws_s3_bucket.static.bucket
}

output "s3_bucket_domain_name" {
  description = "Dominio del bucket S3"
  value       = aws_s3_bucket.static.bucket_domain_name
}

output "s3_bucket_regional_domain_name" {
  description = "Dominio regional del bucket S3"
  value       = aws_s3_bucket.static.bucket_regional_domain_name
}

output "cloudfront_distribution_id" {
  description = "ID de la distribución CloudFront"
  value       = aws_cloudfront_distribution.cdn.id
}

output "cloudfront_domain_name" {
  description = "Dominio de CloudFront"
  value       = aws_cloudfront_distribution.cdn.domain_name
}

output "cloudfront_hosted_zone_id" {
  description = "Hosted Zone ID de CloudFront"
  value       = aws_cloudfront_distribution.cdn.hosted_zone_id
}

# URLs útiles
output "application_urls" {
  description = "URLs principales"
  value = {
    load_balancer = "http://${aws_lb.main.dns_name}"
    cdn           = "https://${aws_cloudfront_distribution.cdn.domain_name}"
  }
}
