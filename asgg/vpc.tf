# ===========================
# VPC CREATION
# ===========================
resource "aws_vpc" "custom_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "custom-vpc"
  }
}

# ===========================
# SUBNETS CREATION
# ===========================
# Public Subnets
resource "aws_subnet" "public_subnet" {
  count                   = length(var.public_subnets)
  vpc_id                  = aws_vpc.custom_vpc.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "Public Subnet ${count.index + 1}"
  }
}

# Private Subnets
resource "aws_subnet" "private_subnet" {
  count             = length(var.private_subnets)
  vpc_id            = aws_vpc.custom_vpc.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "Private Subnet ${count.index + 1}"
  }
}

# ===========================
# INTERNET GATEWAY
# ===========================
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.custom_vpc.id

  tags = {
    Name = "IGW"
  }
}

# ===========================
# ROUTE TABLES
# ===========================
# Public Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.custom_vpc.id

  tags = {
    Name = "Public Route Table"
  }
}

resource "aws_route" "public_internet_route" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_rt_assoc" {
  count          = length(var.public_subnets)
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

# NAT Gateway (For Private Subnets)
resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet[0].id

  tags = {
    Name = "NAT Gateway"
  }
}

# Private Route Table
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.custom_vpc.id

  tags = {
    Name = "Private Route Table"
  }
}

resource "aws_route" "private_nat_route" {
  route_table_id         = aws_route_table.private_rt.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_gw.id
}

resource "aws_route_table_association" "private_rt_assoc" {
  count          = length(var.private_subnets)
  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.private_rt.id
}

# ===========================
# SECURITY GROUPS
# ===========================
# ALB Security Group
resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  vpc_id      = aws_vpc.custom_vpc.id
  description = "Security group for ALB"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 Security Group
resource "aws_security_group" "ec2_sg" {
  name        = "ec2-sg"
  vpc_id      = aws_vpc.custom_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }
  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ===========================
# APPLICATION LOAD BALANCER
# ===========================
resource "aws_lb" "app_lb" {
  name               = "app-lb"
  load_balancer_type = "application"
  subnets            = aws_subnet.public_subnet[*].id
  security_groups    = [aws_security_group.alb_sg.id]
}

resource "aws_lb_target_group" "tg" {
  name     = "web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.custom_vpc.id
}

resource "aws_lb_listener" "alb_listener" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# ===========================
# LAUNCH TEMPLATE & ASG
# ===========================
resource "aws_launch_template" "lt" {
  name_prefix   = "web-lt"
  image_id      = "ami-02b043777a227839c"    #"ami-07b69f62c1d38b012" (linux)"ami-02b043777a227839c"
  instance_type = var.instance_type
  

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.ec2_sg.id]
  }
  #user_data = base64encode(<<EOF
#!/bin/bash
#yum update -y
##yum install -y httpd
#systemctl start httpd
#systemctl enable httpd

# Create dynamic content
#PRIVATE_IP=$(hostname -i)
#echo "<h1>Hi from web server at: $PRIVATE_IP</h1>" > /var/www/html/index.html
#EOF
#  )
}

resource "aws_autoscaling_group" "asg" {
  min_size             = 1
  max_size             = 3
  desired_capacity     = 2
  vpc_zone_identifier  = aws_subnet.private_subnet[*].id
  target_group_arns    = [aws_lb_target_group.tg.arn]
  launch_template {
    id      = aws_launch_template.lt.id
    version = "$Latest"
  }
}

# ===========================
# CLOUDWATCH ALARM FOR CPU UTILIZATION
# ===========================
resource "aws_cloudwatch_metric_alarm" "high_cpu_alarm" {
  alarm_name          = "HighCPUUtilization"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 75
  alarm_description   = "Alarm when CPU exceeds 75%"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.asg.name
  }

  alarm_actions = [aws_autoscaling_policy.scale_out_policy.arn]
}

# ===========================
# AUTO SCALING POLICY
# ===========================
resource "aws_autoscaling_policy" "scale_out_policy" {
  name                   = "ScaleOutPolicy"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.asg.name
}

resource "aws_autoscaling_policy" "scale_in_policy" {
  name                   = "ScaleInPolicy"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.asg.name
}

