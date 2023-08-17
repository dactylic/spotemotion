terraform {
  required_providers {
    aws = {
        source = "hashicorp/aws"
        version = "4.61.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_ecr_repository" "spotemotion_ecr_repo" {
  name = "spotemotion_repo"
}


resource "aws_ecs_cluster" "spotemotion_cluster" {
  name = "spotemotion-cluster"
}


resource "aws_ecs_task_definition" "spotemotion_task" {
  family                = "spotemotion-task-1"
  container_definitions = <<DEFINITION
  [
    {
        "name": "spotemotion-task-1",
        "image": "${aws_ecr_repository.spotemotion_ecr_repo.repository_url}",
        "essential": true,
        "portMappings": 
        [
            {
                "containerPort": 5000,
                "hostPort": 5000
            }
        ],
        "memory": 512,
        "cpu": 256
    }
  ]
  DEFINITION
  requires_compatibilities  = ["FARGATE"]
  network_mode              = "awsvpc"
  memory                    = 512
  cpu                       = 256
  execution_role_arn        = "${aws_iam_role.ecsTaskExecutionRole.arn}"
}


resource "aws_iam_role" "ecsTaskExecutionRole" {
  name                  = "ecsTaskExecutionRole"
  assume_role_policy    = "${data.aws_iam_policy_document.assume_role_policy.json}"
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type          = "Service"
      identifiers   = ["ecs-tasks.amazonaws.com"]
    }
  }
}


resource "aws_iam_role_policy_attachment" "ecsTaskExecutionRole_policy" {
  role          = "${aws_iam_role.ecsTaskExecutionRole.name}"
  policy_arn    = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_default_vpc" "default_vpc" {
}

resource "aws_default_subnet" "default_subnet_a" {
  availability_zone = "us-east-1a"
}

resource "aws_default_subnet" "default_subnet_b" {
  availability_zone = "us-east-1b"
}


resource "aws_alb" "application_load_balancer" {
  name                  = "ljb-fyi-alb"
  load_balancer_type    = "application"
  subnets               = [
    "${aws_default_subnet.default_subnet_a.id}",
    "${aws_default_subnet.default_subnet_b.id}"
  ]
  security_groups = ["${aws_security_group.load_balancer_security_group.id}"]
}

resource "aws_security_group" "load_balancer_security_group" {
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 443
    to_port   = 443
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = -1
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb_target_group" "target_group" {
  name          = "target-group"
  port          = 80
  protocol      = "HTTP"
  target_type   = "ip"
  vpc_id        = "${aws_default_vpc.default_vpc.id}"
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn   = "${aws_alb.application_load_balancer.arn}"
  port                = 443
  protocol            = "HTTPS"
  ssl_policy          = "ELBSecurityPolicy-2016-08"
  certificate_arn     = "arn:aws:acm:us-east-1:300555305453:certificate/55f22999-8ab4-49a1-a8b6-cee5ab7cc9ae"
  default_action {
    type              = "forward"
    target_group_arn  = "${aws_lb_target_group.target_group.arn}"
  }
}

resource "aws_acm_certificate" "certificate" {
  domain_name       = "ljb.fyi"
  validation_method = "DNS"

  tags = {
    Name = "ljb.fyi certificate"
  }
}


resource "aws_route53_zone" "zone" {
  name = "ljb.fyi"
}

resource "aws_lb_listener_certificate" "listener_certificate" {
  listener_arn    = "${aws_lb_listener.listener.arn}"
  certificate_arn = "arn:aws:acm:us-east-1:300555305453:certificate/55f22999-8ab4-49a1-a8b6-cee5ab7cc9ae"
}


resource "aws_lb_listener" "https_listener" {
  load_balancer_arn   = "${aws_alb.application_load_balancer.arn}"
  port                = 443
  protocol            = "HTTPS"
  ssl_policy          = "ELBSecurityPolicy-2016-08"
  certificate_arn     = "${aws_lb_listener_certificate.listener_certificate.certificate_arn}"
  default_action {
    type              = "forward"
    target_group_arn  = "${aws_lb_target_group.target_group.arn}"
  }
  
}

resource "aws_route53_record" "record" {
  zone_id                 = aws_route53_zone.zone.id
  name                    = "ljb.fyi"
  type                    = "A"

  alias {
    name                   = aws_alb.application_load_balancer.dns_name
    zone_id                = aws_alb.application_load_balancer.zone_id
    evaluate_target_health = true
  }
}

resource "aws_ecs_service" "spotemotion_service" {
  name                  = "spotemotion-service-1"
  cluster               = "${aws_ecs_cluster.spotemotion_cluster.id}"
  task_definition       = "${aws_ecs_task_definition.spotemotion_task.arn}"
  launch_type           = "FARGATE"
  desired_count         = 3

  load_balancer {
    target_group_arn    = "${aws_lb_target_group.target_group.arn}"
    container_name      = "${aws_ecs_task_definition.spotemotion_task.family}"
    container_port      = 5000
  }

  network_configuration {
    subnets             = ["${aws_default_subnet.default_subnet_a.id}", "${aws_default_subnet.default_subnet_b.id}"]
    assign_public_ip    = true
    security_groups     = [aws_security_group.default.id]
  }
}

resource "aws_security_group" "service_security_group" {
  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
  security_groups   = ["${aws_security_group.load_balancer_security_group.id}"]
  }
  
  egress {
    to_port         = 0
    from_port       = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "default" {
  name_prefix       = "default-"
  ingress {
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = ["${aws_security_group.load_balancer_security_group.id}"]
  }
  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}

output "alb_dns_name" {
  value = aws_alb.application_load_balancer.dns_name
}