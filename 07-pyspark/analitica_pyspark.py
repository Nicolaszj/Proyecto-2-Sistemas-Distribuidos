"""
PUNTO 7 - Analítica descriptiva con PySpark (API de DataFrames).
Genera la zona refined (gold): una tabla por pregunta de negocio.

El MISMO archivo corre en dos motores Spark, sin cambiar una línea:
  - AWS Glue: job <proyecto>-trusted-a-refined, último paso automático del
    workflow (infra/glue_jobs.tf). Así la API y el tablero siempre tienen datos.
  - Amazon EMR: como "step" con spark-submit (scripts/emr_ejecutar_pasos.sh),
    para mostrar el procesamiento en el clúster.
  - Local:  spark-submit analitica_pyspark.py --DATALAKE file:///tmp/datalake

ENTRA: trusted/{ventas, clientes, productos, paises, tasas_cambio}  (Parquet)
SALE:  refined/p1_... refined/p6_...                              (Parquet)

Las mismas 6 preguntas se responden también con SQL (punto 6) en Athena, Hive
y SparkSQL; los resultados deben coincidir con los de este script.
"""
import sys

from pyspark.sql import SparkSession
from pyspark.sql import functions as F

DIAS = {1: "Lunes", 2: "Martes", 3: "Miércoles", 4: "Jueves", 5: "Viernes", 6: "Sábado", 7: "Domingo"}


def leer_argumentos(argv):
    """['--CLAVE', 'valor', ...] -> {'CLAVE': 'valor'}. Ignora lo que agrega Glue."""
    args = {}
    for i, token in enumerate(argv):
        if token.startswith("--") and i + 1 < len(argv) and not argv[i + 1].startswith("--"):
            args[token[2:]] = argv[i + 1]
    return args


def ventas_enriquecidas(spark, trusted):
    """Une las 3 fuentes en una sola vista de trabajo:
         ventas (EC2) + clientes/países/productos (RDS) + tasas y población (URL)."""
    ventas = spark.read.parquet(f"{trusted}/ventas")
    clientes = spark.read.parquet(f"{trusted}/clientes")
    paises = spark.read.parquet(f"{trusted}/paises")
    productos = spark.read.parquet(f"{trusted}/productos")
    tasas = spark.read.parquet(f"{trusted}/tasas_cambio")
    return (ventas
            .join(clientes, "id_cliente")
            .join(paises, "pais")
            .join(productos, "codigo_producto")
            .join(tasas, "fecha")
            .withColumn("importe_usd", F.col("importe_gbp") * F.col("gbp_usd")))


def solo_ventas(col):
    """Suma/cuenta solo las líneas que NO son devolución."""
    return F.when(~F.col("es_devolucion"), col)


def p1_top_paises_ingreso_usd(v):
    """P1. ¿Cuáles son los 10 países con mayor ingreso neto en dólares?"""
    return (v.groupBy("pais")
             .agg(F.round(F.sum("importe_usd"), 2).alias("ingreso_neto_usd"),
                  F.round(F.sum("importe_gbp"), 2).alias("ingreso_neto_gbp"),
                  F.countDistinct("id_cliente").alias("clientes"))
             .orderBy(F.desc("ingreso_neto_usd"))
             .limit(10))


def p2_ingreso_mensual(v):
    """P2. ¿Cómo evolucionó el ingreso mes a mes y cuál fue el mes pico?"""
    return (v.groupBy(F.year("fecha").alias("anio"), F.month("fecha").alias("mes"))
             .agg(F.round(F.sum("importe_gbp"), 2).alias("ingreso_neto_gbp"),
                  F.round(F.sum("importe_usd"), 2).alias("ingreso_neto_usd"),
                  F.countDistinct(solo_ventas(F.col("factura"))).alias("facturas"),
                  F.round(F.sum(solo_ventas(F.col("importe_gbp")))
                          / F.countDistinct(solo_ventas(F.col("factura"))), 2).alias("ticket_promedio_gbp"))
             # "2011-03": etiqueta lista para el eje X de las gráficas (punto 8)
             .withColumn("periodo", F.format_string("%d-%02d", F.col("anio"), F.col("mes")))
             .orderBy("anio", "mes"))


def p3_top_productos(v):
    """P3. ¿Cuáles son los 10 productos que más ingreso neto generan?"""
    return (v.groupBy("codigo_producto", "descripcion")
             .agg(F.sum("cantidad").alias("unidades_netas"),
                  F.round(F.sum("importe_gbp"), 2).alias("ingreso_neto_gbp"),
                  F.round(F.sum("importe_usd"), 2).alias("ingreso_neto_usd"))
             .orderBy(F.desc("ingreso_neto_gbp"))
             .limit(10))


def p4_gasto_por_habitante(v):
    """P4. ¿En qué países se gasta más en la tienda por cada 1.000 habitantes?"""
    return (v.filter(F.col("poblacion").isNotNull())
             .groupBy("pais", "poblacion", "pib_per_capita_usd")
             .agg(F.round(F.sum("importe_usd"), 2).alias("ingreso_neto_usd"),
                  F.round(F.sum("importe_usd") / F.first("poblacion") * 1000, 4).alias("usd_por_mil_habitantes"))
             .select("pais", "poblacion", "pib_per_capita_usd", "ingreso_neto_usd", "usd_por_mil_habitantes")
             .orderBy(F.desc("usd_por_mil_habitantes"))
             .limit(10))


def p5_devoluciones_por_region(v):
    """P5. ¿Qué región comercial devuelve más (en % del valor vendido)?"""
    brutas = F.sum(F.when(~F.col("es_devolucion"), F.col("importe_gbp")).otherwise(0))
    devueltas = -1 * F.sum(F.when(F.col("es_devolucion"), F.col("importe_gbp")).otherwise(0))
    return (v.groupBy("region_comercial")
             .agg(F.round(brutas, 2).alias("ventas_brutas_gbp"),
                  F.round(devueltas, 2).alias("devoluciones_gbp"),
                  F.round(100 * devueltas / brutas, 2).alias("tasa_devolucion_pct"),
                  F.countDistinct(F.when(F.col("es_devolucion"), F.col("factura"))).alias("facturas_devueltas"))
             .orderBy(F.desc("tasa_devolucion_pct")))


def p6_ventas_dia_hora(v):
    """P6. ¿Qué días de la semana y a qué horas se concentran las compras?"""
    nombre_dia = F.create_map(*[x for k, n in DIAS.items() for x in (F.lit(k), F.lit(n))])
    return (v.filter(~F.col("es_devolucion"))
             .groupBy("dia_semana", "hora")
             .agg(F.countDistinct("factura").alias("facturas"),
                  F.round(F.sum("importe_gbp"), 2).alias("ingreso_bruto_gbp"))
             .withColumn("dia", nombre_dia[F.col("dia_semana")])
             .select("dia_semana", "dia", "hora", "facturas", "ingreso_bruto_gbp")
             .orderBy("dia_semana", "hora"))


PREGUNTAS = [p1_top_paises_ingreso_usd, p2_ingreso_mensual, p3_top_productos,
             p4_gasto_por_habitante, p5_devoluciones_por_region, p6_ventas_dia_hora]


def main():
    args = leer_argumentos(sys.argv)
    datalake = args["DATALAKE"].rstrip("/")
    motor = args.get("MOTOR", "spark")
    spark = SparkSession.builder.appName(f"analitica_pyspark_{motor}").getOrCreate()
    spark.sparkContext.setLogLevel("WARN")
    spark.conf.set("spark.sql.session.timeZone", "UTC")

    v = ventas_enriquecidas(spark, f"{datalake}/trusted").cache()
    print(f"[analitica_pyspark] motor={motor} líneas enriquecidas={v.count()}")

    for pregunta in PREGUNTAS:
        resultado = pregunta(v)
        destino = f"{datalake}/refined/{pregunta.__name__}"
        resultado.coalesce(1).write.mode("overwrite").parquet(destino)
        print(f"\n[analitica_pyspark] {pregunta.__doc__.strip()}  ->  {destino}")
        resultado.show(100, truncate=False)
    spark.stop()


if __name__ == "__main__":
    main()
