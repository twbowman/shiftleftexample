# Sample Terraform with intentional issues for tflint and checkov

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# checkov: CKV_AWS_18 - S3 bucket without access logging
# checkov: CKV_AWS_145 - S3 bucket without KMS encryption
resource "aws_s3_bucket" "data" {
  bucket = "my-insecure-bucket"

  tags = {
    Environment = "dev"
  }
}

# checkov: CKV_AWS_21 - S3 bucket without versioning
resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id
  versioning_configuration {
    status = "Disabled"
  }
}

# checkov: CKV_AWS_23 - Security group with open ingress
resource "aws_security_group" "wide_open" {
  name        = "wide-open-sg"
  description = "Intentionally insecure SG"

  ingress {
    from_port   = 0
    to_port     = 65535
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

# tflint: missing type for variable
variable "instance_type" {
  default = "t3.micro"
}

# checkov: CKV_AWS_8 - EBS not encrypted
resource "aws_instance" "web" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = var.instance_type

  root_block_device {
    volume_size = 20
    encrypted   = false
  }

  tags = {
    Name = "web-server"
  }
}
