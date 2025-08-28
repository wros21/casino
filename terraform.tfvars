# Configuración básica
aws_region     = "ca-central-1"
project_name   = "promarketing"
operation_name = "casino-online"
environment    = "production"

# Configuración de red
main_vpc_cidr = "10.0.0.0/16"
data_vpc_cidr = "10.1.0.0/16"

public_subnet_cidrs = [
  "10.0.1.0/24",
  "10.0.2.0/24"
]

private_subnet_cidrs = [
  "10.0.10.0/24",
  "10.0.20.0/24"
]

database_subnet_cidrs = [
  "10.1.10.0/24",
  "10.1.20.0/24"
]

# Configuración EC2
ami_id         = "ami-0bb9349907edabf10"  # Amazon Linux 2023 en ca-central-1
instance_type  = "t3.micro"
key_pair_name  = "casino-online-keypair"  # Debe existir previamente en AWS

# Configuración Auto Scaling
min_instances     = 2
max_instances     = 6
desired_instances = 3

# Configuración Redis
redis_node_type = "cache.t3.micro"

# Configuración RDS
rds_instance_class    = "db.t3.micro"
rds_allocated_storage = 20
database_name         = "casinodb"
database_username     = "admin"
database_password     = "C4s1n0!0n71n3" 

# Tags comunes
common_tags = {
  Project     = "promarketing"
  Operation   = "casino-online"
  Environment = "production"
  ManagedBy   = "terraform"
  Owner       = "DevOps Team"
  CostCenter  = "IT-Infrastructure"
}