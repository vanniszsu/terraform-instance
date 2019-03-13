variable "hostname" {
  type = "string"
  default = ""
}

variable "env" {
  type = "string"
}

variable "keypair" {
  type = "string"
  default = "markov-key"
}

variable "iamprofile" {
  type = "string"
  default = "ServiceRole-EC2-All"
}

variable "AMI_id" {
  type = "string"
  default = "ami-01bbe152bf19d0289"
  description = "Amazone Linux 2 64bit x86"
}

variable "root_size" {
  default = 8
  description = "Size in GB for the root volume"
}

variable "instance_type" {
  type = "string"
  default = "t3.nano"
}

variable "security_group_ids" {
  type = "list"
}

variable "vpc" {
  type = "string"
  default = "vpc-6428fa02"
}

variable "password" {
  type = "string"
}

data "aws_subnet_ids" "vpc_public_subnets" {
  vpc_id = "${var.vpc}"
  tags {
    env = "${var.env}"
    subnet = "public"
  }
}

data "template_file" "init" {
  template = "${file("./spot-instance/cloudinit.conf")}"
  vars {
    password = "${var.password}"
    v2ray_conf = "${file("./spot-instance/v2ray.config.json")}"
  }
}

resource "random_string" "hostname" {
  length = 12
  special = false
  number = false
  upper = false
}

resource "random_shuffle" "subnet_id" {
  input = ["${data.aws_subnet_ids.vpc_public_subnets.ids}"]
  result_count = 1
}

resource "aws_network_interface" "eth0" {
  security_groups = ["${var.security_group_ids}"]
  subnet_id = "${random_shuffle.subnet_id.result[0]}"
  tags {
    Name = "eth-${var.hostname == "" ? random_string.hostname.result : var.hostname}"
    tenant = "roseatech"
  }
}

resource "aws_spot_instance_request" "sstp-vpn" {
  valid_until = "2099-12-01T23:59:59Z"
  spot_type = "persistent"
  ami           = "${var.AMI_id}"
  instance_type = "${var.instance_type}"
  key_name = "${var.keypair}"
  monitoring = true
  wait_for_fulfillment = true
  ##iam_instance_profile  = "${var.iamprofile}"
  
  user_data = "${data.template_file.init.rendered}"
  
  root_block_device {
    volume_type  = "gp2"
    volume_size = "${var.root_size}"
    delete_on_termination = true
  }
  
  network_interface {
    device_index = 0
    network_interface_id = "${aws_network_interface.eth0.id}"
  }
  
  tags {
    Name = "${var.hostname == "" ? random_string.hostname.result : var.hostname}"
    tenant = "roseatech"
  }
}

output "instance_private_ip" {
  value = "${aws_spot_instance_request.sstp-vpn.private_ip}"
}
output "instance_public_ip" {
  value = "${aws_spot_instance_request.sstp-vpn.public_ip}"
}
output "app_instance_id" {
  value = "${aws_spot_instance_request.sstp-vpn.spot_instance_id}"
}