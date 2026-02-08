########################################
# Provider
########################################
provider "aws" {
  region = var.region
}

terraform {
  backend "s3" {
    bucket = "terraform-state-jenkins-191"
    key    = "terraform-statefile/terraform.tfstate"
    region = "ap-south-1"
  }
}

########################################
# IAM (For Kubernetes LoadBalancer)
########################################
resource "aws_iam_role" "k8s_worker_role" {
  name = "k8's-worker-lb-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "k8s_lb_policy" {
  name = "k8s-lb-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ec2:*",
        "elasticloadbalancing:*",
        "iam:PassRole",
        "iam:CreateServiceLinkedRole"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "attach_lb_policy" {
  role       = aws_iam_role.k8s_worker_role.name
  policy_arn = aws_iam_policy.k8s_lb_policy.arn
}

resource "aws_iam_instance_profile" "k8s_worker_profile" {
  name = "k8s-worker-profile"
  role = aws_iam_role.k8s_worker_role.name
}

########################################
# Security Group
########################################
resource "aws_security_group" "k8s_sg" {
  name        = "k8s-sg"
  description = "Security group for kubeadm Kubernetes cluster"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#######################################
# Master Node
#######################################
resource "aws_instance" "master" {
  ami                    = var.ami
  instance_type          = "t2.medium"
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]

  user_data = <<-EOF
    #!/bin/bash
    set -e
    apt-get update -y
    apt-get install -y python3 python3-apt curl ca-certificates gnupg
    echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu
    chmod 440 /etc/sudoers.d/ubuntu
  EOF

  tags = {
    Name = "k8s-master"
  }
}

########################################
# Elastic IP for Master
########################################
resource "aws_eip" "master_eip" {
  domain = "vpc"

  tags = {
    Name = "k8s-master-eip"
  }
}

resource "aws_eip_association" "master_assoc" {
  instance_id   = aws_instance.master.id
  allocation_id = aws_eip.master_eip.id
}

########################################
# Worker Nodes
########################################
resource "aws_instance" "worker" {
  count                  = var.worker_count
  ami                    = var.ami
  instance_type          = "t2.medium"
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]

  iam_instance_profile = aws_iam_instance_profile.k8s_worker_profile.name

  user_data = <<-EOF
    #!/bin/bash
    set -e
    apt-get update -y
    apt-get install -y python3 python3-apt curl ca-certificates gnupg
    echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu
    chmod 440 /etc/sudoers.d/ubuntu
  EOF

  tags = {
    Name = "k8s-worker-${count.index}"
  }
}

########################################
# Elastic IPs for Workers
########################################
resource "aws_eip" "worker_eip" {
  count  = var.worker_count
  domain = "vpc"

  tags = {
    Name = "k8s-worker-eip-${count.index}"
  }
}

resource "aws_eip_association" "worker_assoc" {
  count         = var.worker_count
  instance_id   = aws_instance.worker[count.index].id
  allocation_id = aws_eip.worker_eip[count.index].id
}