# provider's info
provider "aws" {
  region   = "ap-south-1"
  profile  = "skj"
}

resource "tls_private_key" "webserver_key" {
    algorithm   =  "RSA"
    rsa_bits    =  4096
}

resource "aws_key_pair" "webserver_key" {
    key_name   = "taskey"
    public_key = tls_private_key.webserver_key.public_key_openssh
}


#creating security group 
resource "aws_security_group" "security" {
  name        = "security"
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
resource "aws_instance" "os1" {


  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name      = "taskey"
  security_groups = ["security"]
  connection {
    type = "ssh"
    user = "ec2-user"
    private_key = tls_private_key.webserver_key.private_key_pem
    host    = aws_instance.os1.public_ip
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

#creating volume
resource "aws_ebs_volume" "ebs" {
	availability_zone = aws_instance.os1.availability_zone
	size = 1
	encrypted = "true" 
	tags = {
		Name = "pd1"
	}
}

output "ebs_id" {
	value = aws_ebs_volume.ebs.id
}


#attaching volume
resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.ebs.id
  instance_id = aws_instance.os1.id
  force_detach = true
}

#creating  text file that store ip of os1 
resource "null_resource" "null1"  {
	provisioner "local-exec" {
	    command = "echo  ${aws_instance.os1.public_ip} > os1Ip.txt"
  	}
}

# creating partition of ebs
resource "null_resource" "nullremote1"{

depends_on = [
    aws_volume_attachment.ebs_att,
   
  ]


  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.webserver_key.private_key_pem
    host     = aws_instance.os1.public_ip
  }
provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount  /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/skjshashank/task_repo.git /var/www/html/"
    ]
  }
}

#creating s3 bucket
resource "aws_s3_bucket" "taskbucket" {
  bucket = "skjtaskbucket1"
  acl   = "public-read"
  force_destroy = true
}

# cloning data to local system

resource "null_resource" "null_clone" {
      depends_on = ["aws_s3_bucket.taskbucket"]
      provisioner "local-exec" {
         command = "git clone https://github.com/skjshashank/s3-task.git image"
      }
      
}

#uploading image to bucket

resource "aws_s3_bucket_object" "img" {
depends_on = [null_resource.null_clone]
    bucket = aws_s3_bucket.taskbucket.bucket
    key = "14898.jpg"
    source = "image/14898.jpg"
    acl = "public-read"
}

# creating cloudfront
resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name =  "${aws_s3_bucket.taskbucket.bucket_domain_name}"
    origin_id   =  "S3-${aws_s3_bucket.taskbucket.bucket}"
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "cf using s3"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.taskbucket.bucket}"

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
    target_origin_id = "S3-${aws_s3_bucket.taskbucket.bucket}"


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
resource "null_resource" "null-remote4" {
 depends_on = [ aws_cloudfront_distribution.s3_distribution, ]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.webserver_key.private_key_pem
    host     = aws_instance.os1.public_ip
   }
   provisioner "remote-exec" {
      inline = [
      "sudo su << EOF",
      "echo \"<img src='https://${aws_cloudfront_distribution.s3_distribution.domain_name}/${aws_s3_bucket_object.img.key }' >\" >> /var/www/html/index.php",
       "EOF"
   ]
 }
}


resource "null_resource" "null_launch3"  {

depends_on = [
    null_resource.null-remote4,
  ]

	provisioner "local-exec" {
	    command = "start chrome  ${aws_instance.os1.public_ip}/index.php"
  	}
}
resource "null_resource" "null_launch5"  {

depends_on = [
    null_resource.null-remote4,
  ]

	provisioner "local-exec" {
	    command = "start chrome  ${aws_instance.os1.public_ip}/index.html"
  	}
}
