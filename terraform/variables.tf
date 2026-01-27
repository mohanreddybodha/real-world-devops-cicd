variable "region" {
  description = "AWS region"
  default     = "ap-south-1"
}

variable "ami" {
  description = "AMI ID for EC2 instances"
  default =  "ami-0ff91eb5c6fe7cc86"
}

variable "key_name" {
  description = "SSH key pair name"
  default = "mohan1"
}

variable "worker_count" {
  description = "Number of worker nodes"
  default     = 2
}

variable "admin_ip_cidr" {
  description = "Admin public IP CIDR for SSH / restricted access"
  type        = string
}

output "vpc_id" {
  value = aws_security_group.k8s_sgs.vpc_id
}