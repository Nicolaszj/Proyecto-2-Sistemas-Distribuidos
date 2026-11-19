"""
PUNTO 6 - Consultas SQL con SparkSQL (en EMR).

Ejecuta las MISMAS 6 consultas de 06-consultas-sql/sql/*.sql que corren en
Athena y en Hive: el texto SQL es uno solo y cada motor solo cambia ${db}.

Dos formas de encontrar las tablas (--FUENTE):
  catalogo (por defecto, en EMR): usa el AWS Glue Data Catalog como metastore
            (el clúster se crea con esa configuración en infra/emr.tf), así que
            "retail_trusted.ventas" es la misma tabla que ve Athena.
  rutas     (para probar en un PC): registra vistas temporales leyendo el
            Parquet de trusted directamente.

Uso en EMR (lo hace scripts/emr_ejecutar_pasos.sh):
  spark-submit consultas_sparksql.py --DATALAKE s3://<bucket>
Uso local:
  spark-submit consultas_sparksql.py --DATALAKE file:///tmp/datalake --FUENTE rutas \
      --SQL_DIR file:///ruta/al/repo/06-consultas-sql/sql

Cada resultado se muestra en pantalla (queda en el log del step) y se guarda
en CSV en s3://<bucket>/resultados/sparksql/<pregunta>/ como evidencia.
"""
import os
import sys

from pyspark.sql import SparkSession

TABLAS = ["ventas", "clientes", "productos", "paises", "tasas_cambio"]


def leer_argumentos(argv):
    args = {}
    for i, token in enumerate(argv):
        if token.startswith("--") and i + 1 < len(argv) and not argv[i + 1].startswith("--"):
            args[token[2:]] = argv[i + 1]
    return args


def main():
    args = leer_argumentos(sys.argv)
    datalake = args["DATALAKE"].rstrip("/")
    fuente = args.get("FUENTE", "catalogo")
    sql_dir = args.get("SQL_DIR", f"{datalake}/scripts/06-consultas-sql/sql")

    constructor = SparkSession.builder.appName("consultas_sparksql")
    if fuente == "catalogo":
        constructor = constructor.enableHiveSupport()  # Hive metastore = Glue Data Catalog en EMR
    spark = constructor.getOrCreate()
    spark.sparkContext.setLogLevel("WARN")
    spark.conf.set("spark.sql.session.timeZone", "UTC")

    if fuente == "catalogo":
        db = "retail_trusted"
    else:
        db = "global_temp"
        for tabla in TABLAS:
            spark.read.parquet(f"{datalake}/trusted/{tabla}").createOrReplaceGlobalTempView(tabla)

    # Lee los .sql (desde S3 en EMR, desde disco en local) y los corre en orden.
    consultas = sorted(spark.sparkContext.wholeTextFiles(sql_dir).collect())
    for ruta, texto in consultas:
        nombre = os.path.basename(ruta).replace(".sql", "")
        sql = texto.replace("${db}", db).strip().rstrip(";")
        titulo = next(linea for linea in texto.splitlines() if linea.startswith("-- P")).lstrip("- ")
        print(f"\n[consultas_sparksql] {titulo}")
        resultado = spark.sql(sql)
        resultado.show(100, truncate=False)
        resultado.coalesce(1).write.mode("overwrite").option("header", True) \
            .csv(f"{datalake}/resultados/sparksql/{nombre}")
    spark.stop()


if __name__ == "__main__":
    main()
