"""
PUNTO 3 - Ingesta automática: RDS MariaDB  ->  S3 zona raw.

Job de AWS Glue (Spark, Glue 4.0). Lo crea Terraform (infra/glue_jobs.tf) y lo
dispara el workflow de Glue (infra/glue_workflow.tf) todos los días o a mano.

Cómo llega a la base de datos:
  - El job tiene asociada la "Glue Connection" <proyecto>-conexion-rds (JDBC).
    Esa conexión guarda la URL jdbc:mysql://<endpoint-rds>:3306/retaildb, el
    usuario y la clave, y la subred + security group desde donde Glue entra a
    la VPC. Así la clave NUNCA aparece en el código ni en los argumentos.
  - "useConnectionProperties" le dice a Glue que tome url/usuario/clave de esa
    conexión.

Qué escribe (una "foto" completa de cada tabla por día de ingesta):
  s3://<bucket>/raw/rds/<tabla>/fecha_ingesta=AAAA-MM-DD/part-0000.csv

La zona raw guarda los datos tal cual llegan (CSV, nombres originales). Si el
job corre dos veces el mismo día, sobrescribe la foto de ese día (idempotente).

Argumentos (los pone Terraform en default_arguments):
  --DATALAKE         s3://<bucket>
  --CONNECTION_NAME  nombre de la Glue Connection
  --TABLAS           customers,products,countries
"""
import sys
from datetime import datetime, timezone

from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext

args = getResolvedOptions(sys.argv, ["JOB_NAME", "DATALAKE", "CONNECTION_NAME", "TABLAS"])
datalake = args["DATALAKE"].rstrip("/")
fecha_ingesta = datetime.now(timezone.utc).strftime("%Y-%m-%d")

sc = SparkContext()
glue = GlueContext(sc)
job = Job(glue)
job.init(args["JOB_NAME"], args)

for tabla in args["TABLAS"].split(","):
    tabla = tabla.strip()
    # 1) Leer la tabla completa desde MariaDB usando la conexión de Glue.
    marco = glue.create_dynamic_frame.from_options(
        connection_type="mysql",
        connection_options={
            "useConnectionProperties": "true",
            "connectionName": args["CONNECTION_NAME"],
            "dbtable": tabla,
        },
    )
    df = marco.toDF()
    filas = df.count()

    # 2) Guardarla como CSV con encabezado en la zona raw (un solo archivo).
    destino = f"{datalake}/raw/rds/{tabla}/fecha_ingesta={fecha_ingesta}/"
    df.coalesce(1).write.mode("overwrite").option("header", True).csv(destino)
    print(f"[ingesta_rds] {tabla}: {filas} filas -> {destino}")

job.commit()
