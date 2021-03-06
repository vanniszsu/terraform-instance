provider "aws" {
  profile = "terraform"
  region  = "us-west-2"
}

data "aws_vpc" "default" {
  id = "vpc-0759bbe6e27a45bfe"
}

data "aws_ssm_parameter" "ss_pass" {
  name = "ss_pass"
}

locals {
  userdata = {
    password = "${data.aws_ssm_parameter.ss_pass.value}"
  }    
}

resource "aws_security_group" "vpn" {
  name = "vpn"
  vpc_id = "${data.aws_vpc.default.id}"
  ingress {
    from_port       = 5555
    to_port         = 5555
    protocol        = "tcp"
    cidr_blocks     = ["0.0.0.0/0"]
  }
  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    cidr_blocks     = ["0.0.0.0/0"]
  }
  ingress {
    from_port       = 992
    to_port         = 992
    protocol        = "tcp"
    cidr_blocks     = ["0.0.0.0/0"]
  }
  ingress {
    from_port       = 1194
    to_port         = 1194
    protocol        = "tcp"
    cidr_blocks     = ["0.0.0.0/0"]
  }
  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    cidr_blocks     = ["0.0.0.0/0"]
  }
  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}

###############################

module "vpn_app" {
  source = "./instance-tmpl"
  hostname = "sstp-vpn"
  vpc = "${data.aws_vpc.default.id}"
  env = "prod"
  userdata_params = "${local.userdata}"
  security_group_ids = ["${aws_security_group.vpn.id}"]
}  





