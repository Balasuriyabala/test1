# ===========================
# VARIABLES
# ===========================
variable "region" {
  default = "ap-south-1"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "public_subnets" {
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "availability_zones" {
  default = ["ap-south-1a", "ap-south-1b"]
}

variable "instance_type" {
  default = "m5.xlarge"
   #default = "t2.micro"
}