# PUNTOS 3, 4 y 7 - Jobs de AWS Glue (el código está en las carpetas del repo).
#
#   ingesta-rds        03-ingesta/glue/ingesta_rds.py         RDS  -> raw   (Spark + conexión JDBC)
#   ingesta-url        03-ingesta/glue/ingesta_url.py         URLs -> raw   (Python shell)
#   raw-a-trusted      04-preparacion/glue/raw_a_trusted.py   raw  -> trusted (Spark)
#   trusted-a-refined  07-pyspark/analitica_pyspark.py        trusted -> refined (Spark)
#
# Los 4 usan el rol LabRole y reciben --DATALAKE s3://<bucket>.

# Conexión JDBC de Glue al RDS: guarda URL, usuario y clave, y la subred/SG
# por donde Glue entra a la VPC. El código nunca ve la clave.
resource "aws_glue_connection" "rds" {
  name            = "${var.proyecto}-conexion-rds"
  connection_type = "JDBC"

  connection_properties = {
    JDBC_CONNECTION_URL = "jdbc:mysql://${aws_db_instance.mariadb.address}:${aws_db_instance.mariadb.port}/retaildb"
    USERNAME            = aws_db_instance.mariadb.username
    PASSWORD            = random_password.db.result
  }

  physical_connection_requirements {
    availability_zone      = data.aws_subnet.zona_a.availability_zone
    subnet_id              = data.aws_subnet.zona_a.id
    security_group_id_list = [aws_security_group.glue.id]
  }
}

locals {
  argumentos_comunes = {
    "--DATALAKE"                         = local.datalake
    "--TempDir"                          = "${local.datalake}/tmp/glue/"
    "--job-language"                     = "python"
    "--enable-continuous-cloudwatch-log" = "false"
  }
}

resource "aws_glue_job" "ingesta_rds" {
  name              = "${var.proyecto}-ingesta-rds"
  description       = "PUNTO 3: copia las tablas de MariaDB a raw/rds/ (CSV)"
  role_arn          = local.rol_lab
  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 2
  timeout           = 20
  connections       = [aws_glue_connection.rds.name]

  command {
    name            = "glueetl"
    script_location = "${local.datalake}/scripts/03-ingesta/glue/ingesta_rds.py"
    python_version  = "3"
  }

  default_arguments = merge(local.argumentos_comunes, {
    "--CONNECTION_NAME" = aws_glue_connection.rds.name
    "--TABLAS"          = join(",", local.tablas_rds)
  })

  depends_on = [aws_s3_object.codigo, aws_vpc_endpoint.s3]
}

resource "aws_glue_job" "ingesta_url" {
  name         = "${var.proyecto}-ingesta-url"
  description  = "PUNTO 3: descarga tasas de cambio y datos del Banco Mundial a raw/url/ (JSON)"
  role_arn     = local.rol_lab
  max_capacity = 0.0625
  timeout      = 10

  command {
    name            = "pythonshell"
    script_location = "${local.datalake}/scripts/03-ingesta/glue/ingesta_url.py"
    python_version  = "3.9"
  }

  default_arguments = {
    "--DATALAKE"     = local.datalake
    "--job-language" = "python"
  }

  depends_on = [aws_s3_object.codigo]
}

resource "aws_glue_job" "raw_a_trusted" {
  name              = "${var.proyecto}-raw-a-trusted"
  description       = "PUNTO 4: limpia, tipa y une las fuentes; escribe trusted/ en Parquet"
  role_arn          = local.rol_lab
  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 2
  timeout           = 20

  command {
    name            = "glueetl"
    script_location = "${local.datalake}/scripts/04-preparacion/glue/raw_a_trusted.py"
    python_version  = "3"
  }

  default_arguments = local.argumentos_comunes
  depends_on        = [aws_s3_object.codigo]
}

resource "aws_glue_job" "trusted_a_refined" {
  name              = "${var.proyecto}-trusted-a-refined"
  description       = "PUNTO 7: PySpark responde las 6 preguntas y escribe refined/"
  role_arn          = local.rol_lab
  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 2
  timeout           = 20

  command {
    name            = "glueetl"
    script_location = "${local.datalake}/scripts/07-pyspark/analitica_pyspark.py"
    python_version  = "3"
  }

  default_arguments = merge(local.argumentos_comunes, { "--MOTOR" = "glue" })
  depends_on        = [aws_s3_object.codigo]
}
