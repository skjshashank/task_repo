# provider's info
provider "aws" {
  region   = "ap-south-1"
  profile  = "skj"
}
#-----------------------------------------------------------------------
#VPC CREATION

resource "aws_vpc" "vpc" {
  cidr_block       = "192.168.0.0/16"
  enable_dns_support = "true"
  enable_dns_hostnames = "true"
  instance_tenancy = "default"

  tags = {
    Name = "skjvpc"
  }
}

#--------------------------------------------------------------------------
#SUBNET CREATION

resource "aws_subnet" "subnet1" {
depends_on = [
    aws_vpc.vpc
  ]
  vpc_id     = "${aws_vpc.vpc.id}"
  cidr_block = "192.168.0.0/24"
  availability_zone = "ap-south-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "skjsubnet1"
  }
}

resource "aws_subnet" "subnet2" {
depends_on = [
    aws_vpc.vpc
  ]
  vpc_id     = "${aws_vpc.vpc.id}"
  cidr_block = "192.168.1.0/24"
 availability_zone = "ap-south-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "skjsubnet2"
  }
}

#-------------------------------------------------------------------------
# CREATING IG

resource "aws_internet_gateway" "ig" {
depends_on = [
    aws_vpc.vpc
  ]
  vpc_id = "${aws_vpc.vpc.id}"

  tags = {
    Name = "skjGateway"
  }
}

#----------------------------------------------------------------------------
# ROUTING TABLE


resource "aws_route_table" "rt" {
depends_on = [
    aws_vpc.vpc,
    aws_internet_gateway.ig
  ]
  vpc_id = "${aws_vpc.vpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.ig.id}"
   
  }

  tags = {
    Name = "main"
  }
}

#-----------------------------------------------
# CONNECTING SUBNET AND ROUTING TABLE

resource "aws_route_table_association" "rta" {
depends_on = [
    aws_route_table.rt,
    aws_subnet.subnet1
  ]
  subnet_id      = aws_subnet.subnet1.id
  route_table_id = aws_route_table.rt.id
}
#-------------------------------------------------------------


# creating security group 
resource "aws_security_group" "sec1" {
depends_on = [
    aws_vpc.vpc
  ]
  name        = "allow-wp"
  description = "Allow TLS inbound traffic"
   vpc_id      = "${aws_vpc.vpc.id}"
  

  ingress {
    description = "wp"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "http"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "securityGrpwordpress"
  }
}



# creating security group 
resource "aws_security_group" "sec2" {
depends_on = [
    aws_vpc.vpc
  ]
  name        = "allow-mysql"
  description = "Allow TLS inbound traffic"
   vpc_id      ="${aws_vpc.vpc.id}"
  

  ingress {
    description = "wp"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "http"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    
  }


  tags = {
    Name = "securityGrpmysql"
  }
}
#-----------------------------------------------------------------


#----------------------------------------------------------------------
#creating instance
resource "aws_instance" "wp" {
depends_on = [
    aws_security_group.sec1
  ]

  ami           = "ami-000cbce3e1b899ebd"
  instance_type = "t2.micro"
  key_name      = "task2"
  subnet_id = aws_subnet.subnet1.id
  security_groups = [aws_security_group.sec1.id]
  
 
  tags = {
    Name = "wpos"
  }
}



resource "aws_instance" "sql" {
depends_on = [
    aws_security_group.sec2
  ]

  ami           = "ami-052c08d70def0ac62"
  instance_type = "t2.micro"
  key_name      = "task2"
  subnet_id = aws_subnet.subnet2.id
  security_groups = [aws_security_group.sec2.id]
  user_data=<<-EOF
           #! /bin/bash
           sudo yum install @mysql-y
           systemctl start mysqld
           systemctl enable mysqld
  EOF
  
  
  tags = {
    Name = "mysqlos"
  }
}









