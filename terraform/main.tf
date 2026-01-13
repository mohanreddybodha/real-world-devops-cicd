########################################
# Provider
########################################
provider "aws" {
  region = var.region
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
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 10250
    to_port     = 10250
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
  ami                         = var.ami
  instance_type               = "t2.medium"
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.k8s_sg.id]
  associate_public_ip_address = false

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
  count                       = var.worker_count
  ami                         = var.ami
  instance_type               = "t2.micro"
  key_name                    = var.key_name
  vpc_security_group_ids      = [aws_security_group.k8s_sg.id]
  associate_public_ip_address = false

  tags = {
    Name = "k8s-worker-${count.index}"
  }
}

########################################
# Elastic IPs for Workers
########################################
resource "aws_eip" "worker_eip" {
  count = var.worker_count
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