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

variable "shadowsocks_port" {
  default = 8399
}  

#########################################

data "aws_subnet_ids" "vpc_private_subnets" {
  vpc_id = "${var.vpc}"
  tags {
    env = "${var.env}"
    subnet = "private"
  }
}

data "aws_subnet_ids" "vpc_public_subnets" {
  vpc_id = "${var.vpc}"
  tags {
    env = "${var.env}"
    subnet = "public"
  }
}

data "template_file" "init" {
  template = "${file("./fleet-tmpl/cloudinit.conf")}"
  vars {
    password = "${var.password}"
    port = "${var.shadowsocks_port}"
  }
}

#########################################

resource "random_string" "hostname" {
  length = 12
  special = false
  number = false
  upper = false
}

resource "aws_security_group" "shadowsocks" {
  name = "shadowsocks-spot"
  vpc_id = "${var.vpc}"
  ingress {
    from_port = "${var.shadowsocks_port}"
    to_port = "${var.shadowsocks_port}"
    protocol = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  ingress {
    from_port = "${var.shadowsocks_port}"
    to_port = "${var.shadowsocks_port}"
    protocol = "udp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "all" {
  name = "allow-all"
  vpc_id = "${var.vpc}"
  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}

/*
resource "random_shuffle" "subnet_id" {
  input = ["${data.aws_subnet_ids.vpc_private_subnets.ids}"]
  result_count = 1
}
*/

resource "aws_elb" "shadowsocks_elb" {
  name = "shadowsocks-elb"
  subnets = ["${data.aws_subnet_ids.vpc_public_subnets.ids}"]
  security_groups = ["${aws_security_group.all.id}"]
  internal = false
  listener {
    instance_port = "${var.shadowsocks_port}"
    instance_protocol = "TCP"
    lb_port = "${var.shadowsocks_port}"
    lb_protocol = "TCP"
  }
  health_check {
    healthy_threshold = 3
    unhealthy_threshold = 3
    target = "TCP:${var.shadowsocks_port}"
    interval = 10
    timeout = 5
  }
  tags = {
    tenant = "roseatech"
  }
} 

/*
resource "aws_eip" "lb" {
  count = "${length(data.aws_subnet_ids.vpc_public_subnets.ids)}"
  vpc = true
  tags {
    tenant = "roseatech"
  }
}

resource "aws_lb" "shadowsocks_lb" {
  name = "shadowsocks-lb"
  internal = false
  load_balancer_type = "network"
  enable_cross_zone_load_balancing = true
  subnet_mapping {
    subnet_id = "${data.aws_subnet_ids.vpc_public_subnets.ids[0]}"
    allocation_id = "${aws_eip.lb.*.id[0]}"
  }
  subnet_mapping {
    subnet_id = "${data.aws_subnet_ids.vpc_public_subnets.ids[1]}"
    allocation_id = "${aws_eip.lb.*.id[1]}"
  }
  subnet_mapping {
    subnet_id = "${data.aws_subnet_ids.vpc_public_subnets.ids[2]}"
    allocation_id = "${aws_eip.lb.*.id[2]}"
  }
  ##  Waiting on Terraform 0.12 to use dynamic block to replace those repeative subnet_mapping
  tags = {
    tenant = "roseatech"
  }
}

resource "aws_lb_listener" "shadowsocks_lb" {
  load_balancer_arn = "${aws_lb.shadowsocks_lb.arn}"
  port = "${var.shadowsocks_port}"
  protocol = "TCP"
  default_action {
    type = "forward"
    target_group_arn = "${aws_lb_target_group.shadowsocks_targets.arn}"
  }
}

resource "aws_lb_target_group" "shadowsocks_targets" {
  name = "shadowsocks"
  target_type = "instance"
  port = "${var.shadowsocks_port}"
  protocol = "TCP"
  vpc_id = "${var.vpc}"
  health_check {
    port = "${var.shadowsocks_port}"
    protocol = "TCP"
    healthy_threshold = 3
    unhealthy_threshold = 3
  }
  tags = {
    tenant = "roseatech"
  }
}
*/
resource "aws_spot_fleet_request" "roseatech_instance" {
  valid_until = "2099-12-01T23:59:59Z"
  fleet_type = "maintain"
  terminate_instances_with_expiration = true
  target_capacity = 2
  allocation_strategy = "lowestPrice"
  instance_pools_to_use_count = "${length(data.aws_subnet_ids.vpc_private_subnets.ids)}"
  replace_unhealthy_instances = true
  iam_fleet_role = "arn:aws:iam::225665082421:role/aws-ec2-spot-fleet-tagging-role"
  ## target_group_arns = ["${aws_lb_target_group.shadowsocks_targets.arn}"]  <<< NLB will preserver IP if using instance ID as target
  load_balancers = ["${aws_elb.shadowsocks_elb.name}"]
  
  launch_specification {
      ami           = "${var.AMI_id}"
      instance_type = "${var.instance_type}"
      key_name = "${var.keypair}"
      monitoring = true
      #associate_public_ip_address = false  <<< no such argument
      iam_instance_profile  = "${var.iamprofile}"
      subnet_id = "${data.aws_subnet_ids.vpc_private_subnets.ids[0]}"
      vpc_security_group_ids = ["${concat(var.security_group_ids, list(aws_security_group.shadowsocks.id))}"]
      
      user_data = "${data.template_file.init.rendered}"
  
      root_block_device {
        volume_type  = "gp2"
        volume_size = "${var.root_size}"
        delete_on_termination = true
      }
      
      tags {
        Name = "${var.hostname == "" ? random_string.hostname.result : var.hostname}"
        tenant = "roseatech"
      }
  }
  ##  Waiting on Terraform 0.12 to use dynamic block to replace those repeative subnet_mapping
  launch_specification {
      ami           = "${var.AMI_id}"
      instance_type = "${var.instance_type}"
      key_name = "${var.keypair}"
      monitoring = true
      iam_instance_profile  = "${var.iamprofile}"
      subnet_id = "${data.aws_subnet_ids.vpc_private_subnets.ids[1]}"
      vpc_security_group_ids = ["${concat(var.security_group_ids, list(aws_security_group.shadowsocks.id))}"]
      
      user_data = "${data.template_file.init.rendered}"
  
      root_block_device {
        volume_type  = "gp2"
        volume_size = "${var.root_size}"
        delete_on_termination = true
      }      
      tags {
        Name = "${var.hostname == "" ? random_string.hostname.result : var.hostname}"
        tenant = "roseatech"
      }
  }
  ##  Waiting on Terraform 0.12 to use dynamic block to replace those repeative subnet_mapping
  launch_specification {
      ami           = "${var.AMI_id}"
      instance_type = "${var.instance_type}"
      key_name = "${var.keypair}"
      monitoring = true
      iam_instance_profile  = "${var.iamprofile}"
      subnet_id = "${data.aws_subnet_ids.vpc_private_subnets.ids[2]}"
      vpc_security_group_ids = ["${concat(var.security_group_ids, list(aws_security_group.shadowsocks.id))}"]
      
      user_data = "${data.template_file.init.rendered}"
  
      root_block_device {
        volume_type  = "gp2"
        volume_size = "${var.root_size}"
        delete_on_termination = true
      }      
      tags {
        Name = "${var.hostname == "" ? random_string.hostname.result : var.hostname}"
        tenant = "roseatech"
      }
  }
}  
