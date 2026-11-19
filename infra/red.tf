# Red y firewalls (security groups). Se usa la VPC por defecto de la cuenta.
#
#   ┌──────────── VPC por defecto ───────────────────────────────────────┐
#   │  sg_rds (MariaDB) ◄──3306── sg_fuente (EC2 archivos + extracción)  │
#   │  (el RDS no tiene IP pública; solo entra la EC2 fuente)            │
#   │  sg_app  ◄──8501── internet (tablero Streamlit)                    │
#   │  sg_emr_admin ◄── 22/8888/9443 solo desde ip_administrador         │
#   └────────────────────────────────────────────────────────────────────┘

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

# La base de datos NO es publica: solo entra la EC2 fuente (Glue extrae a traves de ella por SSM).
resource "aws_security_group" "rds" {
  name        = "${var.proyecto}-sg-rds"
  description = "MariaDB: solo desde Glue y desde la EC2 fuente" # texto fijo: cambiarlo recrea el SG; el acceso real es la regla de abajo
  vpc_id      = data.aws_vpc.defecto.id

  ingress {
    description     = "MariaDB desde la EC2 fuente"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.fuente.id]
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
