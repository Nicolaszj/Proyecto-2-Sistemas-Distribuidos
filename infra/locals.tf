# Nombres y rutas que se repiten en varios archivos. Si hay que cambiar un
# nombre, se cambia SOLO aquí.
locals {
  cuenta = data.aws_caller_identity.actual.account_id

  # AWS Academy no deja crear roles IAM: se usan los que ya existen en el lab.
  rol_lab            = "arn:aws:iam::${local.cuenta}:role/LabRole"
  perfil_instancia   = "LabInstanceProfile"
  emr_rol_servicio   = "EMR_DefaultRole"
  emr_perfil_nodos   = "EMR_EC2_DefaultRole"

  # Datalake: un solo bucket con zonas por carpeta. El número de cuenta lo
  # hace único en el mundo.
  bucket   = "${var.proyecto}-datalake-${local.cuenta}"
  datalake = "s3://${local.bucket}"

  # Raíz del repositorio (infra/ está un nivel abajo).
  raiz = "${path.module}/.."

  # Bases de datos del catálogo de Glue (una por zona del datalake).
  db_raw     = "retail_raw"
  db_trusted = "retail_trusted"
  db_refined = "retail_refined"

  # Las 6 preguntas de negocio = 6 archivos SQL = 6 tablas refined.
  preguntas = [
    "p1_top_paises_ingreso_usd",
    "p2_ingreso_mensual",
    "p3_top_productos",
    "p4_gasto_por_habitante",
    "p5_devoluciones_por_region",
    "p6_ventas_dia_hora",
  ]

  tablas_trusted = ["ventas", "clientes", "productos", "paises", "tasas_cambio"]
  tablas_rds     = ["customers", "products", "countries"]
}
