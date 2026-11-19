# Red y firewalls (security groups). Se usa la VPC por defecto de la cuenta.
#
#   ┌──────────── VPC por defecto ───────────────────────────────────────┐
#   │  sg_glue  ──3306──►  sg_rds  ◄──3306──  sg_fuente (EC2 archivos)   │
#   │  (jobs de Glue)      (MariaDB)                                     │
#   │  sg_app  ◄──8501── internet (tablero Streamlit)                    │
#   │  sg_emr_admin ◄── 22/8888/9443 solo desde ip_administrador         │
#   └────────────────────────────────────────────────────────────────────┘

# Glue exige que su security group se permita a sí mismo todo el tráfico TCP
# (los workers de Spark hablan entre ellos).
resource "aws_security_group" "glue" {
  name        = "${var.proyecto}-sg-glue"
  description = "Jobs de Glue con conexion JDBC al RDS"
  vpc_id      = data.aws_vpc.defecto.id

  ingress {
    description = "Trafico entre workers de Glue"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "fuente" {
  name        = "${var.proyecto}-sg-fuente-archivos"
  description = "EC2 fuente de archivos: sin puertos de entrada (se entra por Session Manager)"
  vpc_id      = data.aws_vpc.defecto.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# La base de datos NO es publica: solo entran Glue y la EC2 fuente.
resource "aws_security_group" "rds" {
  name        = "${var.proyecto}-sg-rds"
  description = "MariaDB: solo desde Glue y desde la EC2 fuente"
  vpc_id      = data.aws_vpc.defecto.id

  ingress {
    description     = "MariaDB desde Glue y la EC2 fuente"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.glue.id, aws_security_group.fuente.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "app" {
  name        = "${var.proyecto}-sg-streamlit"
  description = "Tablero Streamlit publico en el puerto 8501"
  vpc_id      = data.aws_vpc.defecto.id

  ingress {
    description = "Streamlit"
    from_port   = 8501
    to_port     = 8501
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Puertos de administración del nodo master del EMR, solo desde el PC del equipo.
resource "aws_security_group" "emr_admin" {
  name        = "${var.proyecto}-sg-emr-admin"
  description = "SSH, Hue y JupyterHub del EMR solo desde ip_administrador"
  vpc_id      = data.aws_vpc.defecto.id

  dynamic "ingress" {
    for_each = {
      "SSH"        = 22
      "Hue"        = 8888
      "JupyterHub" = 9443
      "SparkUI"    = 18080
    }
    content {
      description = ingress.key
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = [var.ip_administrador]
    }
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Los jobs de Glue que entran a la VPC (para leer el RDS) no tienen IP pública:
# este endpoint gratuito les deja escribir en S3 sin salir a internet.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = data.aws_vpc.defecto.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [data.aws_route_table.principal.id]

  tags = { Name = "${var.proyecto}-endpoint-s3" }
}
