provider "aws" {
  version = "~> 2.0"
  region     = var.region
}
# create the VPC
resource "aws_vpc" "My_VPC" {
  cidr_block           = var.vpcCIDRblock
  instance_tenancy     = var.instanceTenancy
  enable_dns_support   = var.dnsSupport
  enable_dns_hostnames = var.dnsHostNames
  tags = {
    Name = "${var.vpcName}-${timestamp()}"
  }
} # end resource
resource "aws_subnet" "public" {
  count = length(var.subnet_cidrs_public)

  vpc_id = aws_vpc.My_VPC.id
  map_public_ip_on_launch = true
  cidr_block = var.subnet_cidrs_public[count.index]
  availability_zone = var.availability_zones[count.index]

  tags={
    Name = "${var.vpcName}-${timestamp()} Subnet ${count.index+1}"
  }
}

# Create the Security Group
resource "aws_default_security_group" "My_VPC_Security_Group" {
  # allow ingress of port 22
  vpc_id = aws_vpc.My_VPC.id
  ingress {
    cidr_blocks = var.ingressCIDRblock
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
  }

  ingress {
    cidr_blocks = var.ingressCIDRblock
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
  }

  ingress {
    cidr_blocks = var.ingressCIDRblock
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
  }

  # allow egress of all ports
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.vpcName}-${timestamp()} Security Group"
    Description = "${var.vpcName}-${timestamp()} Security Group"
  }
} # end resource

# Create the Internet Gateway
resource "aws_internet_gateway" "My_VPC_GW" {
  vpc_id = aws_vpc.My_VPC.id
  tags = {
    Name = "${var.vpcName}-${timestamp()} Internet Gateway"
  }
} # end resource

# Create the Route Table
resource "aws_default_route_table" "My_VPC_route_table" {
  default_route_table_id = aws_vpc.My_VPC.default_route_table_id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.My_VPC_GW.id
  }
  tags = {
    Name = "${var.vpcName}-${timestamp()} Route Table"
  }
} # end resource
# Associate the Route Table with the Subnet
resource "aws_route_table_association" "public" {
  count = length(var.subnet_cidrs_public)

  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_default_route_table.My_VPC_route_table.id
} # end resource
# end vpc.tf