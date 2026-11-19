# Punto 4 · Preparación de datos: raw → trusted (bronze → silver)

> **Enunciado:** procesamiento orientado a la preparación de datos (de raw a trusted), con AWS Glue y Apache Spark.

## Qué hicimos

Un **job de AWS Glue 4.0** (`retail-p2-raw-a-trusted`) escrito en **PySpark** (`glue/raw_a_trusted.py`). Glue es
Spark administrado: 2 workers G.1X sin servidores que mantener. El script es PySpark "puro", así que el mismo
archivo corre en EMR o en un PC (`spark-submit raw_a_trusted.py --DATALAKE file:///ruta`).

```
raw/ec2/ventas/*.csv ─────────────────────────────► trusted/ventas/anio=/mes=/   (Parquet particionado)
raw/rds/customers/  (foto más reciente) ──────────► trusted/clientes/
raw/rds/products/   (foto más reciente) ──────────► trusted/productos/
raw/rds/countries/ + raw/url/worldbank_* ─(join)──► trusted/paises/
raw/url/frankfurter/ ─(calendario + relleno)──────► trusted/tasas_cambio/
                                                    trusted/_reportes/calidad_ventas.json
```

### Qué transforma y por qué

| Transformación | Ejemplo | Para qué |
|---|---|---|
| **Nombres y tipos** estándar | `InvoiceNo` → `factura` (string), `Quantity` → `cantidad` (int), `UnitPrice` → `precio_unitario_gbp` (double), `"12/1/2010 8:26"` → `fecha_hora` (timestamp) | Todas las tablas en español y con tipos correctos |
| **Foto más reciente** | De `fecha_ingesta=2026-11-17` y `=2026-11-18` usa la segunda | Raw guarda historia; trusted refleja el estado actual |
| **Reglas de calidad** sobre ventas (ver tabla) | 541.909 → 399.654 líneas | Solo datos confiables para el análisis |
| **Columnas derivadas** | `importe_gbp`, `fecha`, `hora`, `dia_semana` (1 = lunes), `es_devolucion`, `anio`, `mes` | Las consultas SQL quedan simples e iguales en Athena, Hive y SparkSQL |
| **JSON anidado → tabla** | Banco Mundial `[metadatos, [registros]]` → `iso3, poblacion` | Tablas planas consultables |
| **Enriquecer maestros** | `countries` (RDS) + población y PIB (URL) por `iso3` | `paises` con región, población y PIB |
| **Calendario completo de tasas** | El BCE no publica sábados/domingos/festivos → se usa la última tasa publicada | Toda venta tiene una tasa para pasar a USD |
| **Parquet + particiones** | `ventas/anio=2011/mes=11/` | Formato columnar, comprimido; Athena lee solo lo necesario |

### Reglas de calidad de las ventas (se reportan en `trusted/_reportes/calidad_ventas.json`)

| Regla | Qué elimina | Líneas eliminadas* |
|---|---|---|
| R1_duplicados | líneas exactamente repetidas | 5.270 |
| R2_sin_cliente | líneas sin `CustomerID` (no se puede saber el país) | 135.037 |
| R3_fecha_invalida | fechas que no se pudieron interpretar | 0 |
| R4_cantidad_cero | cantidad 0 o vacía | 0 |
| R5_precio_no_positivo | precio ≤ 0 (ajustes contables) | 40 |
| R6_no_es_producto | portes (`POST`, `DOT`), comisiones, muestras, ajustes, tarjetas regalo | 1.908 |
| R7_producto_sin_maestro | códigos que no existen en el maestro de productos del RDS (integridad entre fuentes) | 0 |
| **Resultado** | 541.909 leídas → **399.654** líneas confiables | |

\* Valores obtenidos al ejecutar el pipeline con el dataset completo.

## Archivos

| Archivo | Qué hace | Lo crea / ejecuta |
|---|---|---|
| `glue/raw_a_trusted.py` | Todo lo anterior. Funciones separadas por tabla: `preparar_clientes`, `preparar_productos`, `preparar_paises`, `preparar_tasas_cambio`, `preparar_ventas` | `infra/glue_jobs.tf` → job `raw-a-trusted`; lo dispara el trigger `t2` del workflow |

## Cómo verificarlo

```bash
scripts/verificar_datalake.sh      # archivos por zona + tablas + reporte de calidad
BUCKET=$(cd infra && terraform output -raw bucket_datalake)
aws s3 ls s3://$BUCKET/trusted/ventas/ --recursive | head
```

En la consola: **Glue → ETL jobs → retail-p2-raw-a-trusted → Runs** (estado, duración, logs en CloudWatch con el
reporte impreso). El script se puede ver en la pestaña **Script** del job.

## Evidencias

| Id | Captura |
|---|---|
| E10 | Glue → `retail-p2-raw-a-trusted` → *Runs*: ejecución *Succeeded* (y pestaña *Script*) |
| E11 | Consola S3: `trusted/` con sus 5 carpetas y `trusted/ventas/anio=2011/` con las particiones por mes |
| E12 | Contenido de `trusted/_reportes/calidad_ventas.json` (desde `scripts/verificar_datalake.sh`) |
