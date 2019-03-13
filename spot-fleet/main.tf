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

data "aws_security_group" "ssh" {
  id = "sg-02657ca86c2122a69"
}

###############################

module "shadowsocks_app" {
  source = "./fleet-tmpl"
  hostname = "shadowsocks-spot-fleet"
  vpc = "${data.aws_vpc.default.id}"
  env = "prod"
  password = "${data.aws_ssm_parameter.ss_pass.value}"
  security_group_ids = ["${data.aws_security_group.ssh.id}"]
}  





