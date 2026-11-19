# PUNTO 5 - Catalogación con AWS Glue (Data Catalog + crawlers).
#
# Una base de datos por zona. Los crawlers recorren las carpetas de S3,
# deducen el esquema (columnas y tipos) y crean/actualizan las tablas.
# Esas tablas son las que consultan Athena (punto 6), SparkSQL y la API.
# (La otra mitad del punto 5, las tablas creadas con Hive en EMR, está en
#  05-catalogacion/hive/crear_tablas_hive.hql.)

resource "aws_glue_catalog_database" "raw" {
  name        = local.db_raw
  description = "Zona raw: datos tal cual llegan (CSV de RDS y EC2)"
}

resource "aws_glue_catalog_database" "trusted" {
  name        = local.db_trusted
  description = "Zona trusted: datos limpios en Parquet"
}

resource "aws_glue_catalog_database" "refined" {
  name        = local.db_refined
  description = "Zona refined: una tabla por pregunta de negocio"
}

# Los CSV de los maestros tienen solo columnas de texto; sin este clasificador
# el crawler no sabría que la primera fila es el encabezado.
resource "aws_glue_classifier" "csv_con_encabezado" {
  name = "${var.proyecto}-csv-con-encabezado"
  csv_classifier {
    contains_header = "PRESENT"
    delimiter       = ","
    quote_symbol    = "\""
  }
}

# Raw: solo los CSV (RDS y EC2). Los JSON de las APIs vienen anidados y se
# convierten en tabla plana en trusted (paises y tasas_cambio).
resource "aws_glue_crawler" "raw" {
  name          = "${var.proyecto}-crawler-raw"
  role          = local.rol_lab
  database_name = aws_glue_catalog_database.raw.name
  classifiers   = [aws_glue_classifier.csv_con_encabezado.name]

  dynamic "s3_target" {
    for_each = concat(["raw/ec2/ventas/"], [for t in local.tablas_rds : "raw/rds/${t}/"])
    content {
      path = "${local.datalake}/${s3_target.value}"
    }
  }
}

resource "aws_glue_crawler" "trusted" {
  name          = "${var.proyecto}-crawler-trusted"
  role          = local.rol_lab
  database_name = aws_glue_catalog_database.trusted.name

  dynamic "s3_target" {
    for_each = local.tablas_trusted
    content {
      path = "${local.datalake}/trusted/${s3_target.value}/"
    }
  }
}

resource "aws_glue_crawler" "refined" {
  name          = "${var.proyecto}-crawler-refined"
  role          = local.rol_lab
  database_name = aws_glue_catalog_database.refined.name

  dynamic "s3_target" {
    for_each = local.preguntas
    content {
      path = "${local.datalake}/refined/${s3_target.value}/"
    }
  }
}
