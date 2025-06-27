
# ----------------------------
# VARIABLES
# ----------------------------
variable "cidr_block" {
  default = "10.10.0.0/16"
}

variable "pub_cidr_1" {
  default = "10.10.10.0/24"
}

variable "pub_cidr_2" {
  default = "10.10.20.0/24"
}

variable "pri_cidr" {
  default = "10.10.30.0/24"
}

# ----------------------------
# VPC & NETWORKING
# ----------------------------
resource "aws_vpc" "main" {
  cidr_block = var.cidr_block

  tags = {
    Name = "main"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "pub1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.pub_cidr_1
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "pub2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.pub_cidr_2
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "pub1" {
  subnet_id      = aws_subnet.pub1.id
  route_table_id = aws_route_table.rt.id
}

resource "aws_route_table_association" "pub2" {
  subnet_id      = aws_subnet.pub2.id
  route_table_id = aws_route_table.rt.id
}

# ----------------------------
# SECURITY GROUPS
# ----------------------------

# ALB SG: allows HTTP from the internet
resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Allow HTTP from the internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
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

# EC2 SG: only allows HTTP from ALB SG
resource "aws_security_group" "ec2_sg" {
  name        = "ec2-sg"
  description = "Allow HTTP from ALB only"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ----------------------------
# LOAD BALANCER
# ----------------------------

resource "aws_lb" "alb" {
  name               = "my-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.pub1.id, aws_subnet.pub2.id]
}

resource "aws_lb_target_group" "tg" {
  name     = "web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path     = "/"
    protocol = "HTTP"
    interval = 30
    timeout  = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# ----------------------------
# IAM FOR EC2 S3 ACCESS
# ----------------------------

resource "aws_iam_role" "ec2_role" {
  name = "ec2_s3_access_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "s3_policy" {
  name = "ec2_s3_policy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = ["s3:GetObject", "s3:ListBucket"],
      Resource = [
        "arn:aws:s3:::chennabuck",
        "arn:aws:s3:::chennabuck/*"
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.s3_policy.arn
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2_instance_profile"
  role = aws_iam_role.ec2_role.name
}

# ----------------------------
# EC2 LAUNCH TEMPLATE & ASG
# ----------------------------

resource "aws_launch_template" "web_template" {
  name_prefix   = "web-template-"
  image_id      = "ami-0c02fb55956c7d316"
  instance_type = "t2.micro"

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  user_data = base64encode(<<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd aws-cli
              systemctl enable httpd
              systemctl start httpd
              echo "Welcome to my page" > /var/www/html/index.html
              EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "web-server"
    }
  }
}

resource "aws_autoscaling_group" "web_asg" {
  name                      = "web-asg"
  min_size                  = 1
  max_size                  = 2
  desired_capacity          = 1
  health_check_type         = "ELB"
  vpc_zone_identifier       = [aws_subnet.pub1.id, aws_subnet.pub2.id]
  target_group_arns         = [aws_lb_target_group.tg.arn]

  launch_template {
    id      = aws_launch_template.web_template.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "web-instance"
    propagate_at_launch = true
  }

  depends_on = [aws_lb_listener.http]
}

# ----------------------------
# ROUTE 53 RECORD (OPTIONAL)
# ----------------------------

data "aws_route53_zone" "zone" {
  name         = "myperwebsite.xyz."
  private_zone = false
}

resource "aws_route53_record" "alb_dns" {
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = "www"
  type    = "A"

  alias {
    name                   = aws_lb.alb.dns_name
    zone_id                = aws_lb.alb.zone_id
    evaluate_target_health = true
  }
}
