# Network Infrastructure

resource "aws_vpc" "cs2_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "cs2-vpc" }
}

resource "aws_internet_gateway" "cs2_igw" {
  vpc_id = aws_vpc.cs2_vpc.id
}

resource "aws_subnet" "cs2_subnet" {
  vpc_id                  = aws_vpc.cs2_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"
}

resource "aws_route_table" "cs2_rt" {
  vpc_id = aws_vpc.cs2_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.cs2_igw.id
  }
}

resource "aws_route_table_association" "cs2_rta" {
  subnet_id      = aws_subnet.cs2_subnet.id
  route_table_id = aws_route_table.cs2_rt.id
}
