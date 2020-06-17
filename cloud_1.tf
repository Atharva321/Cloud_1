provider "aws" {
	region = "us-east-1"
	shared_credentials_file = "C:/Users/HP/aws_credentials/credentials.csv"
	profile = "default"
}
data "aws_region" "current" { name = "us-east-1" }

resource "aws_security_group" "tcp_access3" {
	name = "tcp_access3"
	description = "Lets clients get access"
	
	
	ingress{
		description = "Making TCP port 80 available for HTTP connection "
		from_port = 80
		to_port = 80
		protocol = "tcp"
		cidr_blocks = ["0.0.0.0/0"] 
	}
	
	ingress{
		description = "Secure Access"
		from_port = 22
		to_port =22
		protocol = "tcp"
		cidr_blocks = ["0.0.0.0/0"]
	}


	ingress{
			from_port=8080
			to_port = 8080
			protocol = "tcp"
			cidr_blocks = ["0.0.0.0/0"]

	}
	
	egress {
		from_port = 0
		to_port = 0
		protocol = "-1" #rule to connect to instances from any instances
		cidr_blocks = ["0.0.0.0/0"]
	}
	tags = {
	Name = "tcp_access3"	
}
}
#this will launch the instance
resource "aws_instance" "webserver" {
	#we need to specifiy this in order to create security group first then ami
	depends_on = [
		aws_security_group.tcp_access3 
	]
	ami = "ami-09d95fab7fff3776c"
	instance_type = "t2.micro"
	key_name = "Firstkey1"
	security_groups = ["${aws_security_group.tcp_access3.name}"] 
  
  connection{
		type = "ssh"
		user = "ec2-user"
		private_key = file("C:/Users/HP/aws_credentials/Firstkey1.pem")
		host = aws_instance.webserver.public_ip
	
	}
	
	provisioner "remote-exec" {
		inline =[
			"ls"
		]
	
	}
	tags = {
		Name = "OS_TASK1"	
	}

}

#now creating ebs_volume in which we will write actual webserver code in /var/www/html of emi

resource "aws_ebs_volume" "volume1" {
	availability_zone = aws_instance.webserver.availability_zone
	size = 2
	#size is in GiBs by default
	
	tags = {
		Name = "EBSVOLUME"
	}
	
}
#attaching volume to created instance

resource "aws_volume_attachment" "ebs_att" {
	device_name = "/dev/sdh"  
	volume_id = "${aws_ebs_volume.volume1.id}"
	instance_id = "${aws_instance.webserver.id}"
	
	force_detach = true
}

#Mouting the created volume

resource "null_resource" "nullremote3" {
	depends_on = [
		aws_volume_attachment.ebs_att
	]
	
	connection {
		type = "ssh"
		user = "ec2-user"
		private_key = file("C:/Users/HP/aws_credentials/Firstkey1.pem")
		host = aws_instance.webserver.public_ip
	}
	
	provisioner "remote-exec" {
		inline = [ 
			"sudo yum install php httpd git -y",
			"sudo systemctl restart httpd",
			"sudo systemctl enable httpd",
			#"sudo fdisk /dev/xvdh"
			#"sudo mkdir just_testing"
			"sudo mkfs.ext4 -F /dev/xvdh",
			"sudo mount /dev/xvdh /var/www/html",
			"sudo rm -rf /var/www/html/*",
			"sudo git clone https://github.com/shyamwin/webforcloudtask.git /var/www/html/",
			"sudo systemctl restart httpd"
			]
	}
}


resource "aws_s3_bucket" "tera_bucket"{
	bucket = "shyam-123"
	acl = "public-read"
	
	tags = {
		Name = "Bucket for Website"
	}
}
resource "aws_s3_bucket_public_access_block" "Block_Public_Access"{
	bucket="${aws_s3_bucket.tera_bucket.id}"
	block_public_acls = false
	block_public_policy = false
	restrict_public_buckets = false
	#rember above we gave acl private

}
#putting the data inside s3 bucket
resource "aws_s3_bucket_object" "just_image" {
	bucket = "${aws_s3_bucket.tera_bucket.id}"
	key = "motivation.png"  
	#name of the object when it is in the bucket
	source = "C:/Users/HP/image/terraform.png"
}


#From here this is cloudfront distribution creating for s3 hence we will need identity for s3
locals {
  s3_origin_id = "myS3Origin"
}
resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
	comment = "Access Identity"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
	depends_on = [
		aws_s3_bucket_object.just_image
	]
  origin {
    domain_name = "${aws_s3_bucket.tera_bucket.bucket_regional_domain_name}"
    origin_id   = "${local.s3_origin_id}"

    s3_origin_config {
      origin_access_identity = "${aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path}"
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Access Identity"
  default_root_object  = "motivation.png"
  



  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = true

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # Cache behavior with precedence 0
  ordered_cache_behavior {
    path_pattern     = "/content/immutable/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = true
      headers      = ["Origin"]

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "allow-all"
  }

  # Cache behavior with precedence 1
  ordered_cache_behavior {
    path_pattern     = "/content/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

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
    viewer_protocol_policy = "allow-all"
  }

  price_class = "PriceClass_200"

  restrictions {
    geo_restriction {
      restriction_type = "blacklist"  
      #this is for georestrictions
      locations        = ["US"]
    }
  }

  tags = {
    Environment = "production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
resource "null_resource" "nulllocal1" {
	depends_on = [
		null_resource.nullremote3,
		]
	provisioner "local-exec" {
		command = "start  chrome  ${aws_instance.webserver.public_ip}"
	}

}
output "ec2_ip" {
	value= aws_instance.webserver.public_ip

}
output "cloudfront_url" {
	value = aws_cloudfront_distribution.s3_distribution.domain_name
}

