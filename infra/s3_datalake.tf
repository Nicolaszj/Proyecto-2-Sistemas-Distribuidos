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

# AWS Academy bloquea con una política de la organización (SCP) varias lecturas que
# hace el recurso aws_s3_bucket del provider (por ejemplo
# s3:GetBucketObjectLockConfiguration), y el apply falla aunque el bucket sí se crea.
# Por eso el bucket lo crea la AWS CLI desde un terraform_data: Terraform lo sigue
# creando en el apply y borrando (con todo su contenido) en el destroy.
# Los buckets nuevos de S3 ya vienen privados (Block Public Access) y cifrados (SSE-S3).
resource "terraform_data" "bucket" {
  input = local.bucket

  provisioner "local-exec" {
    command = "aws s3api head-bucket --bucket ${self.input} 2>/dev/null || aws s3api create-bucket --bucket ${self.input} --region ${var.region}"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "aws s3 rb s3://${self.input} --force"
  }
}

# Carpetas vacías de las zonas, para que se vean en la consola desde el inicio.
resource "aws_s3_object" "zonas" {
  for_each = toset(["raw/", "trusted/", "refined/"])
  bucket   = terraform_data.bucket.output
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
  bucket   = terraform_data.bucket.output
  key      = "scripts/${each.value}"
  source   = "${local.raiz}/${each.value}"
  etag     = filemd5("${local.raiz}/${each.value}")
}

# Dataset original (UCI Online Retail). La EC2 fuente lo descarga y lo reparte
# entre sus archivos y el RDS (02-fuentes-de-datos/preparar_fuentes.py).
resource "aws_s3_object" "dataset" {
  bucket = terraform_data.bucket.output
  key    = "seed/online-retail-dataset.csv.zip"
  source = "${local.raiz}/02-fuentes-de-datos/datos/online-retail-dataset.csv.zip"
  etag   = filemd5("${local.raiz}/02-fuentes-de-datos/datos/online-retail-dataset.csv.zip")
}
