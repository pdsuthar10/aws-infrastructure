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
resource "aws_security_group" "Application_SG"  {
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
    from_port   = 443
    to_port     = 443
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
    Name = "${var.vpcName}-${timestamp()} Application - Security Group"
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

# Database Security Group
resource "aws_security_group" "database_sg" {
  name = "database_sg"
  vpc_id = aws_vpc.My_VPC.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups  = [aws_security_group.Application_SG.id]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.egressCIDRblock
  }
  tags = {
    Name = "Database_SG"
    Description = "My Database - Security Group"
  }

}


# S3 Bucket
resource "aws_s3_bucket" "bucket" {
  bucket = var.bucketName
  force_destroy = true
  acl    = "private"

  lifecycle_rule {
    enabled = true

    transition {
      days = 30
      storage_class = "STANDARD_IA"
    }

  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

}


# RDS Database Subnet Group
resource "aws_db_subnet_group" "db_subnet" {
  name       = "db_subnet"
  subnet_ids = [aws_subnet.public[0].id,aws_subnet.public[1].id,aws_subnet.public[2].id]

  tags = {
    Name = "My DB subnet group"
  }
}

# RDS Databse Instance
resource "aws_db_instance" "RDS_Instance" {
  skip_final_snapshot  = true
  engine               = "mysql"
  instance_class       = "db.t2.micro"
  multi_az             = false
  username             = var.db_user
  password             = var.db_password
  identifier           = var.db_identifier
  vpc_security_group_ids  = [aws_security_group.database_sg.id]
  db_subnet_group_name = aws_db_subnet_group.db_subnet.id
  name                 = var.db_name
  publicly_accessible  = false
  allocated_storage    = 20
  storage_type         = "gp2"
  engine_version       = "5.7"
}

#IAM Polciies
resource "aws_iam_policy" "My_S3_Policy" {
  name        = "WebAppS3"
  description = "My S3 Bucket Policy"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:GetObject"
      ],
      "Effect": "Allow",
      "Resource": [
        "arn:aws:s3:::${var.bucketName}",
        "arn:aws:s3:::${var.bucketName}/*"
      ]
    }
  ]
}
EOF
}


# IAM Roles
resource "aws_iam_role" "My_EC2_Role" {
  name = "EC2-CSYE6225"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

# IAM Role Policy Attachment
resource "aws_iam_role_policy_attachment" "attach-policy" {
  role       = aws_iam_role.My_EC2_Role.name
  policy_arn = aws_iam_policy.My_S3_Policy.arn
}

# DynamoDB Table
resource "aws_dynamodb_table" "My_Dynamodb_Table" {
  name           = var.dynamodb_table_name
  billing_mode   = "PROVISIONED"
  read_capacity  = 20
  write_capacity = 20
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }

}


# IAM Instance Profile
resource "aws_iam_instance_profile" "EC2_S3_Role" {
  name = "EC2_S3_Role"
  role =  aws_iam_role.My_EC2_Role.name
}



data "aws_ami" "custom_AMI" {
  owners = ["self"]
  most_recent = true
  filter {
    name = "name"
    values = ["csye6225_*"]
  }
}


# EC2 Instance
resource "aws_instance" "EC2_Instance" {
  ami = data.aws_ami.custom_AMI.id
  instance_type = "t2.micro"
  disable_api_termination = false
  vpc_security_group_ids = [aws_security_group.Application_SG.id]
  key_name = var.ssh_key
  user_data     = templatefile("${path.module}/user_data.sh",
  {
    aws_bucket_name = var.bucketName,
    aws_db_name = aws_db_instance.RDS_Instance.name,
    aws_db_username = aws_db_instance.RDS_Instance.username,
    aws_db_password = aws_db_instance.RDS_Instance.password,
    aws_region = var.region,
    aws_db_host = aws_db_instance.RDS_Instance.address,
    aws_app_port = var.appPort
  })
  iam_instance_profile = aws_iam_instance_profile.EC2_S3_Role.name
  subnet_id = aws_subnet.public[0].id
  associate_public_ip_address = true
  root_block_device {
    volume_type = "gp2"
    volume_size = 20
    delete_on_termination = true
  }
  depends_on = [aws_db_instance.RDS_Instance]
}
# end vpc.tf