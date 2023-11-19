provider "aws" {
  region     = "eu-north-1"
  access_key = ""
  secret_key = ""
}

# Create VPC
resource "aws_vpc" "sre-vps" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "production"
  }
}

# Create AWS GATEWAY
resource "aws_internet_gateway" "sre-gateway" {
  vpc_id = aws_vpc.sre-vps.id

  tags = {
    Name = "prod-gateway"
  }
}

# Creating Route
resource "aws_route_table" "sre-route-table" {
  vpc_id = aws_vpc.sre-vps.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.sre-gateway.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.sre-gateway.id
  }

  tags = {
    Name = "prod-route-table"
  }

}

# Create subnet
resource "aws_subnet" "sre-subnet" {
  vpc_id            = aws_vpc.sre-vps.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "eu-north-1a"

  tags = {
    Name = "prod-subnet"
  }
}

# Associate subnet with Route Table
resource "aws_route_table_association" "sre-associate" {
  subnet_id      = aws_subnet.sre-subnet.id
  route_table_id = aws_route_table.sre-route-table.id
}

# Security group
resource "aws_security_group" "sre-allow-tls" {
  name        = "sre-allow_web_traffic"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.sre-vps.id

  # Ingress policy
  ingress {
    description      = "HTTPS"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  ingress {
    description      = "HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_web"
  }
}

# Creating network interface with an ip in the subnet
resource "aws_network_interface" "sre_web_server-nic" {
  subnet_id       = aws_subnet.sre-subnet.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.sre-allow-tls.id]
}

# Assign an elestic IP to the network interface
resource "aws_eip" "sre-eic" {
  domain                    = "vpc"
  network_interface         = aws_network_interface.sre_web_server-nic.id
  associate_with_private_ip = "10.0.1.50"
  depends_on                = [aws_internet_gateway.sre-gateway]
}

# Nginx Server
resource "aws_instance" "sre-webserver-instance" {
  ami               = "ami-0fe8bec493a81c7da"
  instance_type     = "t3.micro"
  availability_zone = "eu-north-1a"
  key_name          = "sre-key"

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.sre_web_server-nic.id
  }

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update -y
              sudo apt install nginx -y
              sudo systemctl start nginx
              echo '${file("index.html")}' > /var/www/html/index.html
              EOF
  tags = {
    Name = "web-server"
  }
}
