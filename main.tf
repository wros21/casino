############################
# Locales
############################
locals {
  # Acorta nombres para cumplir límites (ALB/TG ≤ 32, Redis ≤ 40, S3 ≤ 63)
  p  = lower(replace(substr(var.project_name, 0, 8), "/[^a-z0-9-]/", ""))
  o  = lower(replace(substr(var.operation_name, 0, 8), "/[^a-z0-9-]/", ""))
  ns = "${local.p}-${local.o}" # namespace corto

  common_tags = merge(
    var.common_tags,
    {
      ProjectNS   = local.ns
      AwsRegion   = var.aws_region
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  )
}

##########################
# Zonas de disponibilidad
##########################
data "aws_availability_zones" "available" {
  state = "available"
}

############################
# VPCs
############################
resource "aws_vpc" "main" {
  cidr_block           = var.main_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = merge(local.common_tags, { Name = "vpc-${local.ns}-main" })
}

resource "aws_vpc" "data" {
  cidr_block           = var.data_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = merge(local.common_tags, { Name = "vpc-${local.ns}-data" })
}

############################
# Subnets
############################
# Base de datos
resource "aws_subnet" "database_subnets" {
  count             = length(var.database_subnet_cidrs)
  vpc_id            = aws_vpc.data.id
  cidr_block        = var.database_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(local.common_tags, {
    Name = "db-subnet-${count.index + 1}"
    Tier = "database"
  })
}

# Públicas
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = merge(local.common_tags, {
    Name = "sub-${local.ns}-pub-${count.index + 1}"
    Tier = "public"
  })
}

# Privadas
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = merge(local.common_tags, {
    Name = "sub-${local.ns}-pri-${count.index + 1}"
    Tier = "private"
  })
}

############################
# Internet Gateway + NAT
############################
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.common_tags, { Name = "igw-${local.ns}" })
}

resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]
  tags       = merge(local.common_tags, { Name = "eip-nat-${local.ns}" })
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  depends_on    = [aws_internet_gateway.igw]
  tags          = merge(local.common_tags, { Name = "nat-${local.ns}" })
}

############################
# Route Tables
############################
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = merge(local.common_tags, { Name = "rt-${local.ns}-pub" })
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = merge(local.common_tags, { Name = "rt-${local.ns}-pri" })
}

resource "aws_route_table_association" "pub_assoc" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "pri_assoc" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

############################
# VPC Peering
############################
resource "aws_vpc_peering_connection" "main_to_data" {
  vpc_id      = aws_vpc.main.id
  peer_vpc_id = aws_vpc.data.id
  auto_accept = true
  tags        = merge(local.common_tags, { Name = "peer-${local.ns}-m2d" })
}

############################
# Security Groups
############################
resource "aws_security_group" "alb" {
  name        = "alb-sg"
  description = "SG para ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ec2" {
  name        = "ec2-sg"
  description = "SG para EC2"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.main_vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "redis" {
  name        = "redis-sg"
  description = "SG para Redis"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds" {
  name        = "rds-sg"
  description = "SG para RDS"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [var.main_vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security group para RDS en la VPC de datos (nuevo)
resource "aws_security_group" "rds_data_vpc" {
  name        = "rds-sg-data"
  description = "Security group para RDS en VPC de datos"
  vpc_id      = aws_vpc.data.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [var.main_vpc_cidr]  # acceso desde VPC principal via peering
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "rds-data-sg" })
}

############################
# ALB + TG
############################
resource "aws_lb" "main" {
  name               = "alb-${local.ns}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for s in aws_subnet.public : s.id]
  enable_deletion_protection = false
  tags = merge(local.common_tags, { Name = "alb-${local.ns}" })
}

resource "aws_lb_target_group" "front" {
  name     = "tg-front-${local.ns}"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/"
    matcher             = "200"
  }

  tags = merge(local.common_tags, { Name = "tg-front-${local.ns}" })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.front.arn
  }
}

############################
# Launch Template
############################
resource "aws_launch_template" "front" {
  name_prefix   = "lt-${local.ns}-front-"
  image_id      = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.ec2.id]

  user_data = base64encode(templatefile("${path.module}/userdata/front-userdata.sh", {
    redis_endpoint = aws_elasticache_cluster.redis.cache_nodes[0].address
    redis_port     = 6379
    port           = 8080
  }))

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, { Name = "ec2-${local.ns}-front" })
  }

  tags = merge(local.common_tags, { Name = "lt-${local.ns}-front" })
}

############################
# ASG
############################
resource "aws_autoscaling_group" "front" {
  name                = "asg-${local.ns}-front"
  vpc_zone_identifier = [for s in aws_subnet.private : s.id]
  target_group_arns   = [aws_lb_target_group.front.arn]
  health_check_type   = "ELB"
  min_size            = var.min_instances
  max_size            = var.max_instances
  desired_capacity    = var.desired_instances

  launch_template {
    id      = aws_launch_template.front.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "ec2-${local.ns}-front"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

############################
# Redis
############################
resource "aws_elasticache_subnet_group" "redis" {
  name       = "redis-sng-${local.ns}"
  subnet_ids = [for s in aws_subnet.private : s.id]
  tags       = merge(local.common_tags, { Name = "redis-sng-${local.ns}" })
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "redis-${local.ns}-1"
  engine               = "redis"
  node_type            = var.redis_node_type
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.redis.name
  security_group_ids   = [aws_security_group.redis.id]
  tags                 = merge(local.common_tags, { Name = "redis-${local.ns}-1" })
}

############################
# RDS MySQL
############################
resource "aws_db_subnet_group" "db_subnets" {
  name       = "rds-sng-${local.ns}"
  subnet_ids = [for s in aws_subnet.database_subnets : s.id]
  tags       = merge(local.common_tags, { Name = "rds-sng-${local.ns}" })
}

resource "aws_db_instance" "data_warehouse" {
  identifier              = "rds-${local.ns}-dw-1"
  allocated_storage       = var.rds_allocated_storage
  storage_type            = "gp3"
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = var.rds_instance_class
  db_name                 = var.database_name
  username                = var.database_username
  password                = var.database_password
  parameter_group_name    = "default.mysql8.0"
  db_subnet_group_name    = aws_db_subnet_group.db_subnets.name
  vpc_security_group_ids  = [aws_security_group.rds_data_vpc.id] # <-- SG de la VPC de datos
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"
  skip_final_snapshot     = true
  publicly_accessible     = false
  multi_az                = false
  tags                    = merge(local.common_tags, { Name = "rds-${local.ns}-dw-1" })
}


############################
# S3 + CloudFront
############################
resource "random_id" "bkt" {
  byte_length = 4
}

resource "aws_s3_bucket" "static" {
  bucket = lower("s3-${local.ns}-static-${random_id.bkt.hex}")
  tags   = merge(local.common_tags, { Name = "s3-${local.ns}-static" })
}

resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "OAI ${local.ns}"
}

resource "aws_s3_bucket_policy" "static" {
  bucket = aws_s3_bucket.static.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid      = "AllowCloudFrontRead"
        Effect   = "Allow"
        Principal = { AWS = aws_cloudfront_origin_access_identity.oai.iam_arn }
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.static.arn}/*"
      }
    ]
  })
}

resource "aws_cloudfront_distribution" "cdn" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "cdn-${local.ns}"

  origin {
    domain_name = aws_s3_bucket.static.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.static.id}"
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.static.id}"

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = merge(local.common_tags, { Name = "cdn-${local.ns}" })
}
