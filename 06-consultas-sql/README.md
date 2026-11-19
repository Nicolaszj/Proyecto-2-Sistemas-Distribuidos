# Punto 6 · Consultas analíticas con SQL: Athena, EMR/Hive y SparkSQL

> **Enunciado:** realizar consultas y procesamiento analítico descriptivo con SQL utilizando AWS Athena, EMR/Hive y SparkSQL.

## Qué hicimos

Escribimos **una sola vez** las 6 consultas (`sql/p1…p6.sql`) y las corremos en **tres motores SQL**. Lo único
que cambia es `${db}`, la base de datos de cada motor:

| Motor | Base de datos (`${db}`) | Cómo reemplaza `${db}` | Cómo se ejecuta |
|---|---|---|---|
| **Amazon Athena** (Trino, serverless) | `retail_trusted` (crawler) | Terraform (`replace(...)` en `infra/athena.tf`) | 6 *Saved queries* en el workgroup `retail-p2-wg` |
| **EMR / Hive** | `retail_hive` (DDL del punto 5) | variable de Hive `--hivevar db=retail_hive` | step con `hive/ejecutar_consultas_hive.sh`, o Hue |
| **EMR / SparkSQL** | `retail_trusted` (Glue Catalog como metastore) | `texto.replace("${db}", db)` en Python | step con `sparksql/consultas_sparksql.py` |

Para que el mismo texto funcione en los tres dialectos, la zona trusted ya trae columnas derivadas (`fecha`,
`hora`, `dia_semana`, `importe_gbp`, `es_devolucion`) y las consultas solo usan SQL estándar (`JOIN`, `GROUP BY`,
`CASE`, `COUNT(DISTINCT …)`, `YEAR()`, `MONTH()`, `ROUND()`). Cada resultado se puede comparar con el de PySpark
(punto 7): **los cuatro deben coincidir**. Lo comprobamos al desarrollar ejecutando las 6 consultas en SparkSQL y en
un motor SQL estilo Trino contra el resultado de PySpark: 6 de 6 iguales.

## Las consultas

| Archivo | Pregunta | Técnicas SQL |
|---|---|---|
| `sql/p1_top_paises_ingreso_usd.sql` | Top 10 países por ingreso neto en USD | 3 tablas (`ventas ⨝ clientes ⨝ tasas_cambio`), conversión por tasa diaria, `COUNT(DISTINCT)` |
| `sql/p2_ingreso_mensual.sql` | Ingreso mensual, facturas y ticket promedio | `GROUP BY YEAR(), MONTH()`, `CASE` dentro de agregados |
| `sql/p3_top_productos.sql` | Top 10 productos por ingreso neto | join con el maestro de productos del RDS |
| `sql/p4_gasto_por_habitante.sql` | Gasto USD por cada 1.000 habitantes | 4 tablas, datos del Banco Mundial, filtro de nulos |
| `sql/p5_devoluciones_por_region.sql` | % devuelto por región comercial | agregación condicional (ventas vs devoluciones) |
| `sql/p6_ventas_dia_hora.sql` | Facturas por día de la semana × hora | doble agrupación, filtro de devoluciones |

## Archivos

| Archivo | Qué hace | Quién lo usa |
|---|---|---|
| `sql/p*.sql` | Las 6 consultas, con `${db}` | Athena (Terraform), Hive, SparkSQL |
| `hive/ejecutar_consultas_hive.sh` | En el master del EMR: baja los `.sql`, corre cada uno con `hive --hivevar db=retail_hive`, guarda en `resultados/hive/` | step "P6 Hive" |
| `sparksql/consultas_sparksql.py` | Lee los `.sql` desde S3, los corre con `spark.sql()` sobre el Glue Catalog, guarda en `resultados/sparksql/` | step "P6 SparkSQL" |
| `../infra/athena.tf` | Workgroup con carpeta de resultados + 6 *named queries* | Terraform |

## Cómo verificarlo

- **Athena:** consola → Athena → *Query editor* → arriba a la derecha *Workgroup* `retail-p2-wg` → pestaña
  *Saved queries* → abrir `p1_top_paises_ingreso_usd` → *Run*.
- **Hive y SparkSQL:** `scripts/emr_ejecutar_pasos.sh` (steps 2 y 3). La salida está en EMR → *Steps* → *View
  logs* → *stdout*, y en `s3://<bucket>/resultados/hive/` y `resultados/sparksql/`.
- **Hive en vivo (Hue):** pegar el contenido de un `.sql` en el editor Hive; Hue muestra una casilla para la
  variable `db`: escribir `retail_hive`.

## Evidencias

| Id | Captura |
|---|---|
| E18 | Athena: lista de *Saved queries* del workgroup `retail-p2-wg` y resultado de P1 |
| E19 | Athena: resultado de P4 o P5 (con "Data scanned" y tiempo de ejecución) |
| E20 | Hive: resultado de una consulta (Hue, o stdout del step "P6 Hive") |
| E21 | SparkSQL: stdout del step "P6 SparkSQL" con las 6 tablas de resultado |
