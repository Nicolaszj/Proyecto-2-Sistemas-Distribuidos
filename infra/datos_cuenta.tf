# Datos que Terraform LEE de la cuenta (no crea nada aquí).

data "aws_caller_identity" "actual" {}

# VPC por defecto de us-east-1 y dos de sus subredes (zonas a y b).
data "aws_vpc" "defecto" {
  default = true
}

data "aws_subnet" "zona_a" {
  vpc_id            = data.aws_vpc.defecto.id
  availability_zone = "${var.region}a"
  default_for_az    = true
}

data "aws_subnet" "zona_b" {
  vpc_id            = data.aws_vpc.defecto.id
  availability_zone = "${var.region}b"
  default_for_az    = true
}

# Imagen más reciente de Amazon Linux 2023 para las EC2.
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}
