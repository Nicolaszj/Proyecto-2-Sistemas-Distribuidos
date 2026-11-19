"""
PUNTO 4 - Preparación de datos: zona raw  ->  zona trusted (bronze -> silver).

Job de AWS Glue (Spark 3, Glue 4.0) escrito en PySpark "puro" (sin librerías
propias de Glue), así que también corre en EMR o en un PC con pyspark:

    spark-submit raw_a_trusted.py --DATALAKE file:///tmp/datalake

Lo dispara el workflow de Glue cuando terminan las dos ingestas (punto 3).

ENTRA (zona raw, tal cual llegó):                 SALE (zona trusted, Parquet):
  raw/ec2/ventas/*.csv            (EC2)    ──►    trusted/ventas/anio=/mes=/
  raw/rds/customers/fecha_ingesta=/ (RDS)  ──►    trusted/clientes/
  raw/rds/products/fecha_ingesta=/  (RDS)  ──►    trusted/productos/
  raw/rds/countries/fecha_ingesta=/ (RDS) ─┐
  raw/url/worldbank_*/ (URL)              ─┴──►   trusted/paises/
  raw/url/frankfurter/ (URL)               ──►    trusted/tasas_cambio/
                                                  trusted/_reportes/calidad_ventas.json

Qué hace "preparar":
  - Estandariza nombres de columnas al español y tipos (int, double, date...).
  - Toma solo la foto más reciente de las fuentes que llegan completas (RDS, URL).
  - Limpia las ventas con reglas de calidad explícitas (ver REGLAS abajo) y
    deja un reporte con cuántas filas eliminó cada regla.
  - Deriva columnas útiles para analizar (importe, fecha, hora, día de semana...)
    para que las consultas SQL sean iguales en Athena, Hive y SparkSQL.
  - Convierte el JSON anidado de las APIs en tablas planas.
  - Rellena las tasas de cambio de fines de semana y festivos con la última
    tasa publicada (el banco no publica esos días, pero la tienda sí vende).
"""
import json
import sys

from pyspark.sql import SparkSession, Window
from pyspark.sql import functions as F
from pyspark.sql import types as T

# Códigos de inventario que NO son productos (portes, comisiones, ajustes,
# muestras, tarjetas regalo...). Se excluyen del análisis de ventas.
CODIGOS_NO_PRODUCTO = ["POST", "DOT", "M", "C2", "D", "S", "B", "BANK CHARGES",
                       "AMAZONFEE", "CRUK", "PADS"]


def leer_argumentos(argv):
    """['--CLAVE', 'valor', ...] -> {'CLAVE': 'valor'}. Ignora lo que agrega Glue."""
    args = {}
    for i, token in enumerate(argv):
        if token.startswith("--") and i + 1 < len(argv) and not argv[i + 1].startswith("--"):
            args[token[2:]] = argv[i + 1]
    return args


def foto_mas_reciente(df):
    """Las fuentes completas (RDS) llegan como una foto por día en carpetas
    fecha_ingesta=AAAA-MM-DD. Spark lee esa carpeta como columna; nos quedamos
    con la más reciente y la quitamos."""
    ultima = df.agg(F.max("fecha_ingesta")).first()[0]
    return df.filter(F.col("fecha_ingesta") == ultima).drop("fecha_ingesta")


def leer_csv_rds(spark, datalake, tabla):
    df = spark.read.option("header", True).csv(f"{datalake}/raw/rds/{tabla}/")
    return foto_mas_reciente(df)


def leer_json_url(spark, datalake, fuente):
    """Devuelve el JSON (ya convertido a objeto Python) de la ingesta más reciente."""
    archivos = spark.sparkContext.wholeTextFiles(f"{datalake}/raw/url/{fuente}/*/{fuente}.json").collect()
    ruta, contenido = max(archivos, key=lambda par: par[0])  # la fecha va en la ruta
    print(f"[raw_a_trusted] {fuente}: usando {ruta}")
    return json.loads(contenido)


# ----------------------------------------------------------------------------
# Tablas maestras (RDS + URL)
# ----------------------------------------------------------------------------
def preparar_clientes(spark, datalake):
    return (leer_csv_rds(spark, datalake, "customers")
            .select(F.col("customer_id").cast("int").alias("id_cliente"),
                    F.trim("country").alias("pais"))
            .dropDuplicates(["id_cliente"]))


def preparar_productos(spark, datalake):
    return (leer_csv_rds(spark, datalake, "products")
            .select(F.upper(F.trim("stock_code")).alias("codigo_producto"),
                    F.trim("description").alias("descripcion"))
            .dropDuplicates(["codigo_producto"]))


def indicador_banco_mundial(spark, datalake, fuente, columna, tipo):
    """El Banco Mundial responde [metadatos, [registros]]. Sacamos iso3 -> valor."""
    _, registros = leer_json_url(spark, datalake, fuente)
    convertir = int if isinstance(tipo, T.LongType) else float
    filas = [(r["countryiso3code"], convertir(r["value"])) for r in registros
             if r.get("countryiso3code") and r.get("value") is not None]
    esquema = T.StructType([T.StructField("iso3", T.StringType()), T.StructField(columna, tipo)])
    return spark.createDataFrame(filas, esquema)


def preparar_paises(spark, datalake):
    paises = (leer_csv_rds(spark, datalake, "countries")
              .select(F.trim("country").alias("pais"),
                      F.when(F.trim("iso3") == "", None).otherwise(F.trim("iso3")).alias("iso3"),
                      F.trim("sales_region").alias("region_comercial")))
    poblacion = indicador_banco_mundial(spark, datalake, "worldbank_poblacion", "poblacion", T.LongType())
    pib = indicador_banco_mundial(spark, datalake, "worldbank_pib", "pib_per_capita_usd", T.DoubleType())
    return (paises.join(poblacion, "iso3", "left")
                  .join(pib, "iso3", "left")
                  .select("pais", "iso3", "region_comercial", "poblacion",
                          F.round("pib_per_capita_usd", 2).alias("pib_per_capita_usd")))


def preparar_tasas_cambio(spark, datalake):
    """Frankfurter responde {"rates": {"2011-01-03": {"USD": 1.55, "EUR": 1.16}, ...}}.
    Se arma un calendario con TODOS los días y se rellenan los días sin tasa
    (fines de semana/festivos) con la última tasa publicada."""
    datos = leer_json_url(spark, datalake, "frankfurter")
    filas = [(fecha, float(t["USD"]), float(t["EUR"])) for fecha, t in datos["rates"].items()]
    publicadas = (spark.createDataFrame(filas, "fecha string, gbp_usd double, gbp_eur double")
                  .withColumn("fecha", F.to_date("fecha")))
    calendario = spark.sql(
        f"SELECT explode(sequence(to_date('{datos['start_date']}'), to_date('{datos['end_date']}'),"
        " interval 1 day)) AS fecha")
    hacia_atras = Window.orderBy("fecha").rowsBetween(Window.unboundedPreceding, 0)
    hacia_adelante = Window.orderBy("fecha").rowsBetween(0, Window.unboundedFollowing)
    unido = calendario.join(publicadas, "fecha", "left")
    return unido.select(
        "fecha",
        F.coalesce(F.last("gbp_usd", True).over(hacia_atras), F.first("gbp_usd", True).over(hacia_adelante)).alias("gbp_usd"),
        F.coalesce(F.last("gbp_eur", True).over(hacia_atras), F.first("gbp_eur", True).over(hacia_adelante)).alias("gbp_eur"),
        F.col("gbp_usd").isNotNull().alias("es_tasa_publicada"),
    )


# ----------------------------------------------------------------------------
# Ventas (EC2): limpieza con reglas de calidad
# ----------------------------------------------------------------------------
def preparar_ventas(spark, datalake, productos):
    crudo = spark.read.option("header", True).csv(f"{datalake}/raw/ec2/ventas/")
    tipado = crudo.select(
        F.trim("InvoiceNo").alias("factura"),
        F.upper(F.trim("StockCode")).alias("codigo_producto"),
        F.col("Quantity").cast("int").alias("cantidad"),
        F.to_timestamp("InvoiceDate", "M/d/yyyy H:mm").alias("fecha_hora"),
        F.col("UnitPrice").cast("double").alias("precio_unitario_gbp"),
        F.col("CustomerID").cast("double").cast("int").alias("id_cliente"),
    )

    # Cada regla: (nombre, explicación, función que deja solo las filas buenas)
    reglas = [
        ("R1_duplicados", "Líneas exactamente repetidas", lambda d: d.dropDuplicates()),
        ("R2_sin_cliente", "Sin CustomerID: no se puede saber el país",
         lambda d: d.filter(F.col("id_cliente").isNotNull())),
        ("R3_fecha_invalida", "Fecha que no se pudo interpretar",
         lambda d: d.filter(F.col("fecha_hora").isNotNull())),
        ("R4_cantidad_cero", "Cantidad 0 o vacía",
         lambda d: d.filter(F.col("cantidad").isNotNull() & (F.col("cantidad") != 0))),
        ("R5_precio_no_positivo", "Precio unitario <= 0 (ajustes contables)",
         lambda d: d.filter(F.col("precio_unitario_gbp") > 0)),
        ("R6_no_es_producto", "Portes, comisiones, muestras y tarjetas regalo",
         lambda d: d.filter(~F.col("codigo_producto").isin(CODIGOS_NO_PRODUCTO)
                            & ~F.col("codigo_producto").startswith("GIFT_"))),
        ("R7_producto_sin_maestro", "Código que no existe en el maestro de productos (RDS)",
         lambda d: d.join(F.broadcast(productos.select("codigo_producto")), "codigo_producto", "left_semi")),
    ]

    reporte = {"filas_leidas": tipado.count(), "reglas": []}
    actual = tipado
    filas_antes = reporte["filas_leidas"]
    for nombre, explicacion, regla in reglas:
        actual = regla(actual).cache()
        filas_despues = actual.count()
        reporte["reglas"].append({"regla": nombre, "explicacion": explicacion,
                                  "filas_eliminadas": filas_antes - filas_despues})
        filas_antes = filas_despues
    reporte["filas_finales"] = filas_antes

    ventas = actual.select(
        "factura", "codigo_producto", "cantidad", "precio_unitario_gbp",
        F.round(F.col("cantidad") * F.col("precio_unitario_gbp"), 2).alias("importe_gbp"),
        "id_cliente", "fecha_hora",
        F.to_date("fecha_hora").alias("fecha"),
        F.hour("fecha_hora").alias("hora"),
        # dayofweek de Spark: 1=domingo..7=sábado. Lo pasamos a ISO: 1=lunes..7=domingo
        (((F.dayofweek("fecha_hora") + 5) % 7) + 1).alias("dia_semana"),
        F.col("factura").startswith("C").alias("es_devolucion"),  # facturas "C..." = devoluciones
        F.year("fecha_hora").alias("anio"),
        F.month("fecha_hora").alias("mes"),
    )
    return ventas, reporte


def guardar(df, ruta, particiones=None):
    escritor = (df.repartition(*particiones) if particiones else df.coalesce(1)).write.mode("overwrite")
    if particiones:
        escritor = escritor.partitionBy(*particiones)
    escritor.parquet(ruta)


def escribir_texto(spark, ruta, texto):
    """Escribe un archivo de texto único en S3 o disco usando el FileSystem de Hadoop
    (funciona igual en Glue, EMR y local)."""
    jvm = spark.sparkContext._jvm
    conf = spark.sparkContext._jsc.hadoopConfiguration()
    path = jvm.org.apache.hadoop.fs.Path(ruta)
    fs = path.getFileSystem(conf)
    salida = fs.create(path, True)
    salida.write(bytearray(texto.encode("utf-8")))
    salida.close()


def main():
    args = leer_argumentos(sys.argv)
    datalake = args["DATALAKE"].rstrip("/")
    spark = SparkSession.builder.appName("raw_a_trusted").getOrCreate()
    spark.sparkContext.setLogLevel("WARN")
    spark.conf.set("spark.sql.session.timeZone", "UTC")
    spark.conf.set("spark.sql.sources.partitionOverwriteMode", "static")

    clientes = preparar_clientes(spark, datalake)
    productos = preparar_productos(spark, datalake)
    paises = preparar_paises(spark, datalake)
    tasas = preparar_tasas_cambio(spark, datalake)
    ventas, reporte = preparar_ventas(spark, datalake, productos)

    trusted = f"{datalake}/trusted"
    guardar(clientes, f"{trusted}/clientes")
    guardar(productos, f"{trusted}/productos")
    guardar(paises, f"{trusted}/paises")
    guardar(tasas, f"{trusted}/tasas_cambio")
    guardar(ventas, f"{trusted}/ventas", particiones=["anio", "mes"])

    texto = json.dumps(reporte, ensure_ascii=False, indent=2)
    escribir_texto(spark, f"{trusted}/_reportes/calidad_ventas.json", texto)

    print("[raw_a_trusted] Reporte de calidad de ventas:\n" + texto)
    for nombre, df in [("clientes", clientes), ("productos", productos), ("paises", paises),
                       ("tasas_cambio", tasas)]:
        print(f"[raw_a_trusted] {nombre}: {df.count()} filas")
    spark.stop()


if __name__ == "__main__":
    main()
