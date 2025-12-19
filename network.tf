# Get available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC for Palworld server
resource "aws_vpc" "palworld" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# Public subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.palworld.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "palworld" {
  vpc_id = aws_vpc.palworld.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# Route table for public subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.palworld.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.palworld.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# Associate route table with public subnet
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Security group for Palworld server
resource "aws_security_group" "palworld" {
  name        = "${var.project_name}-sg"
  description = "Security group for Palworld dedicated server"
  vpc_id      = aws_vpc.palworld.id

  # SSH access
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = local.ssh_allowed_cidrs
  }

  # HTTP for monitoring dashboard
  ingress {
    description = "HTTP for monitoring dashboard"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Palworld game port (UDP)
  ingress {
    description = "Palworld game port"
    from_port   = 8211
    to_port     = 8211
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Steam query port (UDP)
  ingress {
    description = "Steam query port"
    from_port   = 27015
    to_port     = 27015
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # RCON port (for server management)
  ingress {
    description = "RCON for server management"
    from_port   = 25575
    to_port     = 25575
    protocol    = "tcp"
    cidr_blocks = local.rcon_allowed_cidrs
  }

  # Allow all outbound traffic
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg"
  }
}
