variable "hostname" {
  type = "string"
  default = ""
}

variable "env" {
  type = "string"
  default = "app"
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
}

variable "userdata_params" {
  type = "map"
  default = {}
}  

#########################################

data "aws_subnet_ids" "default_vpc_subnets" {
  vpc_id = "${var.vpc}"
  tags {
    env = "${var.env}"
    subnet = "public"
  }
}

data "template_file" "init" {
  template = "${file("./instance-tmpl/cloudinit.conf")}"
  vars = "${var.userdata_params}"
}

#########################################

resource "random_string" "hostname" {
  length = 12
  special = false
  number = false
  upper = false
}

resource "random_shuffle" "subnet_id" {
  input = ["${data.aws_subnet_ids.default_vpc_subnets.ids}"]
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

resource "aws_eip" "instance_ip" {
  vpc = true
  network_interface = "${aws_network_interface.eth0.id}"
  tags {
    tenant = "roseatech"
  }
}

resource "aws_instance" "roseatech_instance" {
  ami           = "${var.AMI_id}"
  instance_type = "${var.instance_type}"
  key_name = "${var.keypair}"
  monitoring = true
  #iam_instance_profile  = "${var.iamprofile}"
  
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
  volume_tags {
    Name = "vol-${var.hostname == "" ? random_string.hostname.result : var.hostname}"
    tenant = "roseatech"
  }
}  
   
output "instance_private_ip" {
  value = "${aws_instance.roseatech_instance.private_ip}"
}
output "instance_public_ip" {
  value = "${aws_instance.roseatech_instance.public_ip}"
}
output "app_instance_id" {
  value = "${aws_instance.roseatech_instance.id}"
}