provider "aws" {
  version = "~> 2.0"
  region     = var.region
}
###########################
#         VPC             #
###########################
resource "aws_vpc" "My_VPC" {
  cidr_block           = var.vpcCIDRblock
  instance_tenancy     = var.instanceTenancy
  enable_dns_support   = var.dnsSupport
  enable_dns_hostnames = var.dnsHostNames
  tags = {
    Name = "${var.vpcName}-${timestamp()}"
  }
}

data "aws_availability_zones" "availability_zones" {}

resource "aws_subnet" "public" {
  count = length(var.subnet_cidrs_public)

  vpc_id = aws_vpc.My_VPC.id
  map_public_ip_on_launch = true
  cidr_block = var.subnet_cidrs_public[count.index]
  availability_zone = data.aws_availability_zones.availability_zones.names[count.index]

  tags={
    Name = "${var.vpcName}-${timestamp()} Subnet ${count.index+1}"
  }
}

###########################
#     ROUTE TABLE         #
###########################
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

###########################
#     LOAD BALANCER SG    #
###########################
resource "aws_security_group" "loadBalancer_SG" {
  name          = "Load Balancer SG (Webapp)"
  vpc_id        =  aws_vpc.My_VPC.id

  ingress{
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks  = var.ingressCIDRblock
  }

  ingress{
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks  = var.ingressCIDRblock
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = var.egressCIDRblock
  }

  tags = {
    Description = "Load Balancer Security Group for WEBAPP project"
  }
}


###########################
#     APPLICATION SG      #
###########################
resource "aws_security_group" "Application_SG"  {
  vpc_id = aws_vpc.My_VPC.id

  ingress {
    cidr_blocks = var.ingressCIDRblock
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    security_groups = [aws_security_group.loadBalancer_SG.id]
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

###########################
#     INTERNET GATEWAY    #
###########################
resource "aws_internet_gateway" "My_VPC_GW" {
  vpc_id = aws_vpc.My_VPC.id
  tags = {
    Name = "${var.vpcName}-${timestamp()} Internet Gateway"
  }
} # end resource

###########################
#       DATABASE SG       #
###########################
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


###################################
#         S3 BUCKET               #
###################################
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

resource "aws_s3_bucket_public_access_block" "s3Public" {
  bucket = aws_s3_bucket.bucket.id
  ignore_public_acls = true
  block_public_acls = true
  block_public_policy = true
  restrict_public_buckets = true
}


###################################
#               RDS               #
###################################
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
  instance_class       = "db.t3.micro"
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


###################################
#      IAM POLICIES               #
###################################
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

# Policy for EC2 Role
# This policy allows to read & upload data from S3 bucket
resource "aws_iam_policy" "CodeDeploy-EC2-S3" {
  name = "CodeDeploy-EC2-S3"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:Get*",
        "s3:List*"
      ],
      "Effect": "Allow",
      "Resource": [
        "arn:aws:s3:::codedeploy.${var.environment}.${var.domainName}/*"
      ]
    }
  ]
}
EOF
}

resource "aws_iam_policy" "GH-Upload-To-S3" {
  name = "GH-Upload-To-S3"
  policy = <<EOF
{
  "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:Get*",
                "s3:List*"
            ],
            "Resource": [
                "arn:aws:s3:::codedeploy.${var.environment}.${var.domainName}",
                "arn:aws:s3:::codedeploy.${var.environment}.${var.domainName}/*",
                "arn:aws:s3:::lambda.${var.environment}.${var.domainName}/*"
            ]
        }
    ]
}
EOF
}

resource "aws_iam_policy" "GH-Lambda" {
  name = "GH-Lambda"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "lambda:*"
        ],

      "Resource": "arn:aws:lambda:${var.region}:${local.user_account_id}:function:${aws_lambda_function.lambda_sns_updates.function_name}"
    }
  ]
}
EOF
}

data "aws_caller_identity" "current" {}

locals {
  user_account_id = data.aws_caller_identity.current.account_id
}

resource "aws_iam_policy" "GH-Code-Deploy" {
  name = "GH-Code-Deploy"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "codedeploy:RegisterApplicationRevision",
        "codedeploy:GetApplicationRevision"
      ],
      "Resource": [
        "arn:aws:codedeploy:${var.region}:${local.user_account_id}:application:${aws_codedeploy_app.code_deploy_app.name}"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "codedeploy:CreateDeployment",
        "codedeploy:GetDeployment"
      ],
      "Resource": [
        "arn:aws:codedeploy:${var.region}:${local.user_account_id}:deploymentgroup:${aws_codedeploy_app.code_deploy_app.name}/${aws_codedeploy_deployment_group.code_deploy_deployment_group.deployment_group_name}"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "codedeploy:GetDeploymentConfig"
      ],
      "Resource": [
        "arn:aws:codedeploy:${var.region}:${local.user_account_id}:deploymentconfig:CodeDeployDefault.OneAtATime",
        "arn:aws:codedeploy:${var.region}:${local.user_account_id}:deploymentconfig:CodeDeployDefault.HalfAtATime",
        "arn:aws:codedeploy:${var.region}:${local.user_account_id}:deploymentconfig:CodeDeployDefault.AllAtOnce"
      ]
    }
  ]
}
EOF
}

resource "aws_iam_policy" "GH-Packer" {
  name = "GH-Packer"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "ec2:AttachVolume",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:CopyImage",
      "ec2:CreateImage",
      "ec2:CreateKeypair",
      "ec2:CreateSecurityGroup",
      "ec2:CreateSnapshot",
      "ec2:CreateTags",
      "ec2:CreateVolume",
      "ec2:DeleteKeyPair",
      "ec2:DeleteSecurityGroup",
      "ec2:DeleteSnapshot",
      "ec2:DeleteVolume",
      "ec2:DeregisterImage",
      "ec2:DescribeImageAttribute",
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceStatus",
      "ec2:DescribeRegions",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSnapshots",
      "ec2:DescribeSubnets",
      "ec2:DescribeTags",
      "ec2:DescribeVolumes",
      "ec2:DetachVolume",
      "ec2:GetPasswordData",
      "ec2:ModifyImageAttribute",
      "ec2:ModifyInstanceAttribute",
      "ec2:ModifySnapshotAttribute",
      "ec2:RegisterImage",
      "ec2:RunInstances",
      "ec2:StopInstances",
      "ec2:TerminateInstances"
    ],
    "Resource" : "*"
  }]
}
EOF
}

resource "aws_iam_user_policy_attachment" "ghactions_s3_policy_attach" {
  policy_arn = aws_iam_policy.GH-Upload-To-S3.arn
  user = data.aws_iam_user.deployUser.user_name
}

resource "aws_iam_user_policy_attachment" "ghactions_codedeploy_policy_attach" {
  policy_arn = aws_iam_policy.GH-Code-Deploy.arn
  user = data.aws_iam_user.deployUser.user_name
}

resource "aws_iam_user_policy_attachment" "ghactions_packer_policy_attach" {
  policy_arn = aws_iam_policy.GH-Packer.arn
  user = data.aws_iam_user.deployUser.user_name
}

resource "aws_iam_user_policy_attachment" "ghactions_lambda_policy_attach" {
  policy_arn = aws_iam_policy.GH-Lambda.arn
  user = data.aws_iam_user.deployUser.user_name
}

data "aws_iam_user" "deployUser" {
  user_name = "ghactions"
}

###################################
#      IAM ROLES                  #
###################################
resource "aws_iam_role" "My_EC2_Role" {
  name = "CodeDeployEC2ServiceRole"

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

resource "aws_iam_role_policy_attachment" "codedeploy-ec2-s3-attach-policy" {
  role       = aws_iam_role.My_EC2_Role.name
  policy_arn = aws_iam_policy.CodeDeploy-EC2-S3.arn
}


###################################
#          DYNAMO DB              #
###################################
resource "aws_dynamodb_table" "My_Dynamodb_Table" {
  name           = var.dynamodb_table_name
  billing_mode   = "PROVISIONED"
  read_capacity  = 20
  write_capacity = 20
  hash_key       = "email_hash"

  attribute {
    name = "email_hash"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled = true
  }

  tags = {
    Name = var.dynamodb_table_name
  }
}


###################################
#      IAM INSTANCE PROFILE       #
###################################
resource "aws_iam_instance_profile" "EC2_S3_Role" {
  name = "EC2_S3_Role"
  role =  aws_iam_role.My_EC2_Role.name
}

###################################



data "aws_ami" "custom_AMI" {
  owners = [var.dev_account]
  filter {
    name = "name"
    values = ["csye6225_*"]
  }
  most_recent = true
}

###################################
#      EC2 INSTANCE               #
###################################
//resource "aws_instance" "EC2_Instance" {
//  ami = data.aws_ami.custom_AMI.id
//  instance_type = "t2.micro"
//  disable_api_termination = false
//  vpc_security_group_ids = [aws_security_group.Application_SG.id]
//  key_name = var.ssh_key
//  user_data     = templatefile("${path.module}/user_data.sh",
//  {
//    aws_bucket_name = var.bucketName,
//    aws_db_name = aws_db_instance.RDS_Instance.name,
//    aws_db_username = aws_db_instance.RDS_Instance.username,
//    aws_db_password = aws_db_instance.RDS_Instance.password,
//    aws_region = var.region,
//    aws_db_host = aws_db_instance.RDS_Instance.address,
//    aws_app_port = var.appPort
//  })
//  iam_instance_profile = aws_iam_instance_profile.EC2_S3_Role.name
//  subnet_id = aws_subnet.public[0].id
//  associate_public_ip_address = true
//  root_block_device {
//    volume_type = "gp2"
//    volume_size = 20
//    delete_on_termination = true
//  }
//  depends_on = [aws_db_instance.RDS_Instance]
//  tags = {
//    Name = "Webapp Server"
//    WebappServer = "CI/CD"
//  }
//}

###################################
#      CODE DEPLOY                #
###################################
resource "aws_iam_role" "CodeDeployServiceRole" {
  name = "CodeDeployServiceRole"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "codedeploy.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "AWSCodeDeployRole" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
  role       = aws_iam_role.CodeDeployServiceRole.name
}

resource "aws_iam_role_policy_attachment" "CloudWatchAgent_EC2Policy" {
  role = aws_iam_role.My_EC2_Role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}



resource "aws_codedeploy_app" "code_deploy_app" {
  compute_platform = "Server"
  name             = "csye6225-webapp"
}

resource "aws_codedeploy_deployment_group" "code_deploy_deployment_group" {
  app_name                = aws_codedeploy_app.code_deploy_app.name
  deployment_group_name   = "csye6225-webapp-deployment"
  deployment_config_name  = "CodeDeployDefault.AllAtOnce"
  service_role_arn        = aws_iam_role.CodeDeployServiceRole.arn
  autoscaling_groups      = [aws_autoscaling_group.autoscaling_group.name]

  load_balancer_info {
    target_group_info {
      name = aws_lb_target_group.alb-target-group.name
    }
  }

  alarm_configuration {
    alarms = ["Deployment-Alarm"]
    enabled = true
  }

  ec2_tag_filter {
    key   = "WebappServer"
    type  = "KEY_AND_VALUE"
    value = "CI/CD"
  }

  deployment_style {
    deployment_option = "WITHOUT_TRAFFIC_CONTROL"
    deployment_type   = "IN_PLACE"
  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }

  depends_on = [aws_codedeploy_app.code_deploy_app]
}

###################################
#   ASG LAUNCH CONFIGURATION      #
###################################
resource "aws_launch_configuration" "ASG_LaunchConfiguration" {
  name            = "ASG Launch Configuration (Webapp)"
  image_id        = data.aws_ami.custom_AMI.id
  instance_type   = "t2.micro"
  security_groups = [aws_security_group.Application_SG.id]
  key_name        = var.ssh_key
  user_data       = templatefile("${path.module}/user_data.sh",
  {
    aws_bucket_name = var.bucketName,
    aws_db_name = aws_db_instance.RDS_Instance.name,
    aws_db_username = aws_db_instance.RDS_Instance.username,
    aws_db_password = aws_db_instance.RDS_Instance.password,
    aws_region = var.region,
    aws_db_host = aws_db_instance.RDS_Instance.address,
    aws_app_port = var.appPort,
    aws_environment = var.environment,
    aws_domainName = var.domainName,
    aws_topic_arn = aws_sns_topic.user_updates.arn
  })
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.EC2_S3_Role.name
  root_block_device {
    volume_type = "gp2"
    volume_size = "20"
    delete_on_termination = true
  }

  depends_on = [aws_db_instance.RDS_Instance]
}

###################################
#        LB TARGET GROUP          #
###################################
resource "aws_lb_target_group" "alb-target-group" {

  name     = "ALB-targetGroup-Webapp"
  port     = "3000"
  protocol = "HTTP"
  vpc_id   = aws_vpc.My_VPC.id

  tags     = {
    name = "alb-target-group"
  }

  health_check {
    healthy_threshold   = 3
    unhealthy_threshold = 5
    timeout             = 5
    interval            = 30
    path                = "/healthstatus"
    port                = "3000"
    matcher             = "200"
  }
}

###################################
#          LOAD BALANCER          #
###################################
resource "aws_lb" "application-loadBalancer" {
  internal           = false
  load_balancer_type = "application"
  security_groups    = [ aws_security_group.loadBalancer_SG.id ]
  subnets            = aws_subnet.public.*.id
  ip_address_type    = "ipv4"
  tags = {
    Environment = var.environment
    Name = "ALB-Webapp"
  }
}

resource "aws_lb_listener" "webapp-listener" {
  load_balancer_arn = aws_lb.application-loadBalancer.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb-target-group.arn
  }
}

###################################
#       ROUTE 53 - ALB            #
###################################
data "aws_route53_zone" "selected" {
  name         = "${var.environment}.${var.domainName}"
  private_zone = false
}
# Alias Record for ALB
resource "aws_route53_record" "www" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = data.aws_route53_zone.selected.name
  type    = "A"

  alias {
    name = aws_lb.application-loadBalancer.dns_name
    zone_id = aws_lb.application-loadBalancer.zone_id
    evaluate_target_health = true
  }
}


###################################
#              ASG                #
###################################
resource "aws_autoscaling_group" "autoscaling_group" {
  name                 = "ASG-Webapp"
  launch_configuration = aws_launch_configuration.ASG_LaunchConfiguration.name
  min_size             = 3
  max_size             = 5
  default_cooldown     = 60
  desired_capacity     = 3

  vpc_zone_identifier = aws_subnet.public.*.id

  target_group_arns    = [ aws_lb_target_group.alb-target-group.arn ]

  tag {
    key                 = "WebappServer"
    value               = "CI/CD"
    propagate_at_launch = true
  }
}

# ASG POLICIES
resource "aws_autoscaling_policy" "server-scaleUp-policy" {
  name                   = "Server-ScaleUp-Policy"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 60
  autoscaling_group_name = aws_autoscaling_group.autoscaling_group.name
}

resource "aws_autoscaling_policy" "server-scaleDown-policy" {
  name                   = "Server-ScaleDown-Policy"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 60
  autoscaling_group_name = aws_autoscaling_group.autoscaling_group.name
}

## ASG RULES / METRICS TO WATCH
resource "aws_cloudwatch_metric_alarm" "CPU-High-Alarm" {
  alarm_name          = "CPU-High-Alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Average"
  threshold           = "5"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.autoscaling_group.name
  }
  alarm_description = "Scale-up if CPU Utilization > 5% for 1 minute"
  alarm_actions     = [ aws_autoscaling_policy.server-scaleUp-policy.arn ]
}

resource "aws_cloudwatch_metric_alarm" "CPU-Low-Alarm" {
  alarm_name          = "CPU-Low-Alarm"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Average"
  threshold           = "3"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.autoscaling_group.name
  }
  alarm_description = "Scale-down if CPU Utilization < 3% for 1 minute"
  alarm_actions     = [ aws_autoscaling_policy.server-scaleDown-policy.arn ]
}


############################
#            SNS           #
############################
resource "aws_sns_topic" "user_updates" {
  name = "user_updates"
}

data "aws_iam_policy_document" "sns_topic_policy" {

  statement {
    actions = [
      "SNS:Subscribe",
      "SNS:SetTopicAttributes",
      "SNS:RemovePermission",
      "SNS:Receive",
      "SNS:Publish",
      "SNS:ListSubscriptionsByTopic",
      "SNS:GetTopicAttributes",
      "SNS:DeleteTopic",
      "SNS:AddPermission",
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceOwner"

      values = [
        local.user_account_id,
      ]
    }

    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    resources = [
      aws_sns_topic.user_updates.arn,
    ]
  }
}

resource "aws_sns_topic_policy" "user_updates_policy" {
  arn = aws_sns_topic.user_updates.arn
  policy = data.aws_iam_policy_document.sns_topic_policy.json
}

# IAM policy for SNS
resource "aws_iam_policy" "sns_iam_policy" {
  name = "ec2_iam_policy"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "SNS:Publish"
      ],
      "Resource": "${aws_sns_topic.user_updates.arn}"
    }
  ]
}
EOF
}

# Attach the SNS topic policy to the EC2 role
resource "aws_iam_role_policy_attachment" "ec2_sns" {
  policy_arn = aws_iam_policy.sns_iam_policy.arn
  role = aws_iam_role.My_EC2_Role.name
}



###########################
#       LAMBDA            #
###########################

#IAM role for lambda
resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

#lambda function
resource "aws_lambda_function" "lambda_sns_updates" {
  filename      = "lambda_function_payload.zip"
  function_name = "lambda_email_updates"
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "index.handler"

  # The filebase64sha256() function is available in Terraform 0.11.12 and later
  # For Terraform 0.11.11 and earlier, use the base64sha256() function and the file() function:
  # source_code_hash = "${base64sha256(file("lambda_function_payload.zip"))}"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")

  runtime = "nodejs12.x"
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${var.lambda_function_name}"
}

resource "aws_lambda_alias" "lambda_alias" {
  name             = "email-notification"
  description      = "Lambda alias for sending emails to users"
  function_name    = aws_lambda_function.lambda_sns_updates.arn
  function_version = "$LATEST"
}

#SNS topic subscription to Lambda
resource "aws_sns_topic_subscription" "lambda" {
  topic_arn = aws_sns_topic.user_updates.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.lambda_sns_updates.arn
}

#SNS Lambda permission
resource "aws_lambda_permission" "allow_from_sns" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_sns_updates.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.user_updates.arn
}

#Lambda Policy
resource "aws_iam_policy" "lambda_policy" {
  name        = "lambda_policy"
  description = "Policy for cloud watch and code deploy"
  policy      = <<EOF
{
   "Version": "2012-10-17",
   "Statement": [
       {
           "Effect": "Allow",
           "Action": [
               "logs:CreateLogGroup"
           ],
           "Resource": "*"
       },
        {
           "Effect": "Allow",
           "Action": [
               "logs:CreateLogStream",
               "logs:PutLogEvents"
           ],
           "Resource": "*"
       },
       {
         "Sid": "LambdaDynamoDBAccess",
         "Effect": "Allow",
         "Action": [
             "dynamodb:GetItem",
             "dynamodb:PutItem",
             "dynamodb:UpdateItem"
         ],
         "Resource": "arn:aws:dynamodb:${var.region}:${local.user_account_id}:table/${var.dynamodb_table_name}"
       },
       {
         "Sid": "LambdaSESAccess",
         "Effect": "Allow",
         "Action": [
             "ses:VerifyEmailAddress",
             "ses:SendEmail",
             "ses:SendRawEmail"
         ],
         "Resource": "*",
          "Condition":{
            "StringEquals":{
              "ses:FromAddress":"${var.fromAddress}@${var.environment}.${var.domainName}"
            }
          }
       }
   ]
}
 EOF
}

#Attach the policy for Lambda iam role
resource "aws_iam_role_policy_attachment" "lambda_role_policy_attach" {
  role       = aws_iam_role.iam_for_lambda.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}



