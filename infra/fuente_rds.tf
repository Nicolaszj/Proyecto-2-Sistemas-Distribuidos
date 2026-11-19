# PUNTO 2 - Fuente 1: base de datos RDS MariaDB (datos maestros del "ERP").
# La crea vacía; la EC2 fuente le carga el esquema y los datos al arrancar
# (02-fuentes-de-datos/sql/esquema_mariadb.sql + INSERTs generados).

resource "random_password" "db" {
  length  = 20
  special = false # sin símbolos para no tener problemas de comillas en bash/JDBC
}

resource "aws_db_subnet_group" "rds" {
  name       = "${var.proyecto}-subredes-rds"
  subnet_ids = [data.aws_subnet.zona_a.id, data.aws_subnet.zona_b.id]
}

resource "aws_db_instance" "mariadb" {
  identifier     = "${var.proyecto}-mariadb"
  engine         = "mariadb"
  engine_version = var.db_version
  instance_class = var.db_clase

  allocated_storage = 20
  storage_type      = "gp2"

  db_name  = "retaildb"
  username = "admin"
  password = random_password.db.result
  port     = 3306

  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false # nadie desde internet; solo Glue y la EC2 fuente

  multi_az                = false
  backup_retention_period = 0 # laboratorio: sin backups (crea más rápido)
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true
}
