# PUNTOS 3, 4 y 7 - El datalake en Amazon S3.
#
# s3://<proyecto>-datalake-<cuenta>/
#   raw/        datos tal cual llegan de las fuentes (CSV y JSON)     <- punto 3
#   trusted/    datos limpios y tipados en Parquet                    <- punto 4
#   refined/    respuestas a las preguntas de negocio en Parquet      <- punto 7
#   scripts/    copia del código del repo que ejecutan Glue, EMR y las EC2
#   seed/       dataset original (solo lo usa la EC2 fuente al arrancar)
#   resultados/ salidas de Hive y SparkSQL (evidencias del punto 6)
#   athena-results/, emr-logs/, tmp/   carpetas técnicas

resource "aws_s3_bucket" "datalake" {
  bucket        = local.bucket
  force_destroy = true # terraform destroy borra el bucket aunque tenga archivos
}

resource "aws_s3_bucket_public_access_block" "datalake" {
  bucket                  = aws_s3_bucket.datalake.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "datalake" {
  bucket = aws_s3_bucket.datalake.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Carpetas vacías de las zonas, para que se vean en la consola desde el inicio.
resource "aws_s3_object" "zonas" {
  for_each = toset(["raw/", "trusted/", "refined/"])
  bucket   = aws_s3_bucket.datalake.id
  key      = each.value
  content  = ""
}

# Todo el código que corre en AWS se sube desde el repo a scripts/<misma ruta>.
# Si se edita un archivo, el etag cambia y "terraform apply" lo vuelve a subir.
locals {
  archivos_codigo = setunion(
    fileset(local.raiz, "02-fuentes-de-datos/*.py"),
    fileset(local.raiz, "02-fuentes-de-datos/sql/*.sql"),
    fileset(local.raiz, "03-ingesta/**/*.py"),
    fileset(local.raiz, "03-ingesta/**/*.sh"),
    fileset(local.raiz, "04-preparacion/**/*.py"),
    fileset(local.raiz, "05-catalogacion/**/*.hql"),
    fileset(local.raiz, "06-consultas-sql/**/*.sql"),
    fileset(local.raiz, "06-consultas-sql/**/*.py"),
    fileset(local.raiz, "06-consultas-sql/**/*.sh"),
    fileset(local.raiz, "07-pyspark/*.py"),
    fileset(local.raiz, "08-visualizacion-y-api/streamlit/*"),
  )
}

resource "aws_s3_object" "codigo" {
  for_each = local.archivos_codigo
  bucket   = aws_s3_bucket.datalake.id
  key      = "scripts/${each.value}"
  source   = "${local.raiz}/${each.value}"
  etag     = filemd5("${local.raiz}/${each.value}")
}

# Dataset original (UCI Online Retail). La EC2 fuente lo descarga y lo reparte
# entre sus archivos y el RDS (02-fuentes-de-datos/preparar_fuentes.py).
resource "aws_s3_object" "dataset" {
  bucket = aws_s3_bucket.datalake.id
  key    = "seed/online-retail-dataset.csv.zip"
  source = "${local.raiz}/02-fuentes-de-datos/datos/online-retail-dataset.csv.zip"
  etag   = filemd5("${local.raiz}/02-fuentes-de-datos/datos/online-retail-dataset.csv.zip")
}
