/*
===========================================
NOMAD APPLICATION LOAD BALANCER (ALB)
===========================================
Layer 7 ALB with TLS termination for Nomad
Nomad internally uses self-signed certificates
*/

/*
Application Load Balancer for Nomad
Requires at least 2 subnets in different AZs
*/
resource "aws_lb" "nomad_alb" {
  name               = "nomad-alb-${substr(random_string.random_name.result, 0, 4)}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.nomad_alb_sg.id]
  subnets            = [aws_subnet.main.id, aws_subnet.public_az2.id]

  enable_deletion_protection       = false
  enable_cross_zone_load_balancing = true

  tags = {
    Name        = "nomad-alb"
    Environment = var.environment
    Purpose     = "nomad-load-balancer"
  }
}

/*
Security Group for ALB
*/
resource "aws_security_group" "nomad_alb_sg" {
  name_prefix = "nomad-alb-sg"
  vpc_id      = aws_vpc.main.id
  description = "Security group for Nomad Application Load Balancer"

  ingress {
    description = "HTTPS from Internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from Internet on API port"
    from_port   = 4646
    to_port     = 4646
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "nomad-alb-security-group"
    Environment = var.environment
  }
}

/*
Import ACME certificate to AWS Certificate Manager (ACM)
Required for TLS termination on ALB

For AWS ACM:
- certificate_body: Server certificate only
- certificate_chain: Full intermediate certificate chain (issuer_pem from Let's Encrypt)

Let's Encrypt provides:
- certificate_pem: Server certificate
- issuer_pem: Intermediate CA chain (includes Let's Encrypt intermediate and root)
*/
resource "aws_acm_certificate" "nomad_cert" {
  private_key       = local.nomad_key
  certificate_body  = local.nomad_cert
  certificate_chain = local.nomad_ca

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "nomad-acme-certificate"
    Environment = var.environment
    Purpose     = "nomad-tls-termination"
  }

  depends_on = [acme_certificate.nomad_certificate]
}

/*
Target Group for Nomad HTTPS API (port 4646)
Backend uses HTTPS with self-signed certificates
*/
resource "aws_lb_target_group" "nomad_https" {
  name     = "nomad-https-${substr(random_string.random_name.result, 0, 4)}"
  port     = 4646
  protocol = "HTTPS"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 10
    interval            = 30
    protocol            = "HTTPS"
    path                = "/v1/status/leader"
    matcher             = "200"
  }

  deregistration_delay = 30

  # This is crucial - allows ALB to connect to backend with self-signed cert
  stickiness {
    type    = "lb_cookie"
    enabled = false
  }

  tags = {
    Name        = "nomad-https-target-group"
    Environment = var.environment
  }
}

/*
Register Nomad server instance to target group
*/
resource "aws_lb_target_group_attachment" "nomad_https" {
  target_group_arn = aws_lb_target_group.nomad_https.arn
  target_id        = aws_instance.nomad_server.id
  port             = 4646
}

/*
ALB Listener for HTTPS (port 443) with TLS termination
*/
resource "aws_lb_listener" "nomad_https_443" {
  load_balancer_arn = aws_lb.nomad_alb.arn
  port              = "443"
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate.nomad_cert.arn
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nomad_https.arn
  }

  tags = {
    Name        = "nomad-https-listener-443"
    Environment = var.environment
  }
}

/*
ALB Listener for HTTPS (port 4646) with TLS termination
For direct Nomad API compatibility
*/
resource "aws_lb_listener" "nomad_https_4646" {
  load_balancer_arn = aws_lb.nomad_alb.arn
  port              = "4646"
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate.nomad_cert.arn
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nomad_https.arn
  }

  tags = {
    Name        = "nomad-https-listener-4646"
    Environment = var.environment
  }
}
