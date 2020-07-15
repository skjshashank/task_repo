# provider's info
provider "aws" {
  region   = "ap-south-1"
  profile  = "skj"
}

resource "tls_private_key" "webserver_key2" {
    algorithm   =  "RSA"
    rsa_bits    =  4096
}

resource "aws_key_pair" "webserver_key2" {
    key_name   = "taskey2"
    public_key = tls_private_key.webserver_key2.public_key_openssh
}


#creating security group 
resource "aws_security_group" "security" {
  name        = "security2"
  description = "Allow TLS inbound traffic"
  

  ingress {
    description = "ssh"
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
    Name = "securityGrp"
  }
}

#creating instance
resource "aws_instance" "os2" {
depends_on = [
    aws_key_pair.webserver_key2,
   
  ]

  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name      = "taskey2"
  security_groups = ["security2"]
  connection {
    type = "ssh"
    user = "ec2-user"
    private_key = tls_private_key.webserver_key2.private_key_pem
    host    = aws_instance.os2.public_ip
  } 

  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }
  tags = {
    Name = "taskos"
  }
}

#creating file syste (efs)
resource "aws_efs_file_system" "efs" {

	creation_token = "efs"
	tags = {
		Name = "efs"
	}
}



#attaching efs volume
resource "aws_efs_mount_target" "efs_att" {
depends_on = [
    aws_efs_file_system.efs,
  ]
  file_system_id = aws_efs_file_system.efs.id
  subnet_id = aws_instance.os2.subnet_id
}

#creating  text file that store ip of os1 
resource "null_resource" "null1"  {
	provisioner "local-exec" {
	    command = "echo  ${aws_instance.os2.public_ip} > os1Ip.txt"
  	}
}

# creating partition of ebs
resource "null_resource" "nullremote1"{

depends_on = [
    aws_efs_mount_target.efs_att,
   
  ]

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.webserver_key2.private_key_pem
    host     = aws_instance.os2.public_ip
  }
provisioner "remote-exec" {
    inline = [
      "sudo echo ${aws_efs_file_system.efs.dns_name}:/var/www/html efs defaults,_netdev 0 0 >> sudo /etc/fstab",
      "sudo mount  ${aws_efs_file_system.efs.dns_name}:/  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/skjshashank/task_repo.git /var/www/html/"
    ]
  }
}

#creating s3 bucket
resource "aws_s3_bucket" "taskbucket2" {
  bucket = "skjtaskbucket2"
  acl   = "public-read"
  force_destroy = true
}

# cloning data to local system

resource "null_resource" "null_clone" {
      depends_on = ["aws_s3_bucket.taskbucket2"]
      provisioner "local-exec" {
         command = "git clone https://github.com/skjshashank/s3-task.git image"
      }
      
}

#uploading image to bucket

resource "aws_s3_bucket_object" "img2" {
depends_on = [null_resource.null_clone]
    bucket = aws_s3_bucket.taskbucket2.bucket
    key = "14898.jpg"
    source = "image/14898.jpg"
    acl = "public-read"
}

# creating cloudfront
resource "aws_cloudfront_distribution" "s3_distribution2" {
  origin {
    domain_name =  "${aws_s3_bucket.taskbucket2.bucket_domain_name}"
    origin_id   =  "S3-${aws_s3_bucket.taskbucket2.bucket}"
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "cf using s3"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.taskbucket2.bucket}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # Cache behavior with precedence 1
  ordered_cache_behavior {
    path_pattern     = "/content/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.taskbucket2.bucket}"


    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }
  
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Environment = "cloud_production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
resource "null_resource" "null-remote3" {
 depends_on = [ aws_cloudfront_distribution.s3_distribution2, 
     null_resource.nullremote1
]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.webserver_key2.private_key_pem
    host     = aws_instance.os2.public_ip
   }
   provisioner "remote-exec" {
      inline = [
      "sudo su << EOF",
      "echo \"<img src='https://${aws_cloudfront_distribution.s3_distribution2.domain_name}/${aws_s3_bucket_object.img2.key }' >\" >> /var/www/html/index.php",
       "EOF"
   ]
 }
}


resource "null_resource" "null_launch1"  {

depends_on = [
    null_resource.null-remote3,
  ]

	provisioner "local-exec" {
	    command = "start chrome  ${aws_instance.os2.public_ip}/index.php"
  	}
}

