# Punto 5 · Catalogación de tablas: AWS Glue y EMR/Hive

> **Enunciado:** realizar catalogación de tablas SQL con herramientas como AWS Glue y EMR/Hive.

## Qué hicimos

Catalogamos con las **dos** herramientas, sobre el mismo **AWS Glue Data Catalog**:

### 1. AWS Glue: crawlers (automático, dentro del workflow)

`infra/glue_catalogo.tf` crea una base de datos por zona y un crawler por zona:

| Crawler | Recorre | Crea tablas en | Tablas |
|---|---|---|---|
| `retail-p2-crawler-raw` | `raw/ec2/ventas/`, `raw/rds/{customers,products,countries}/` | `retail_raw` | ventas, customers, products, countries (CSV) |
| `retail-p2-crawler-trusted` | `trusted/{ventas,clientes,productos,paises,tasas_cambio}/` | `retail_trusted` | 5 tablas Parquet (ventas con particiones `anio`, `mes`) |
| `retail-p2-crawler-refined` | `refined/p1_…/` … `refined/p6_…/` | `retail_refined` | 6 tablas Parquet, una por pregunta |

- Un **clasificador CSV** con `contains_header = PRESENT`: los maestros solo tienen columnas de texto y, sin él,
  el crawler tomaría el encabezado como un dato más.
- Los JSON de las APIs no se catalogan en raw (vienen anidados); se vuelven tablas planas en trusted (`paises`,
  `tasas_cambio`).

### 2. EMR/Hive: DDL explícito (`hive/crear_tablas_hive.hql`)

El clúster EMR (`infra/emr.tf`) se crea con la clasificación `hive-site` →
`hive.metastore.client.factory.class = AWSGlueDataCatalogHiveClientFactory`: **el metastore de Hive ES el Glue
Data Catalog**. El script crea la base `retail_hive` con **tablas externas** (`CREATE EXTERNAL TABLE … STORED AS
PARQUET LOCATION 's3://…/trusted/…'`) y registra las particiones de ventas con `MSCK REPAIR TABLE`.

Consecuencia que se muestra en la demo: **una tabla creada en Hive aparece sola en la consola de Glue y se puede
consultar desde Athena**, y una tabla creada por un crawler se puede consultar desde Hive y SparkSQL en EMR.

| | Crawler de Glue | DDL en Hive |
|---|---|---|
| Esquema | lo deduce leyendo los archivos | lo escribimos nosotros (tipos y comentarios) |
| Particiones | las detecta solo | `MSCK REPAIR TABLE` |
| Ventaja | automático, se adapta a cambios | control total del esquema y documentación |
| Dónde queda | Glue Data Catalog | Glue Data Catalog (vía metastore de Hive) |

## Archivos

| Archivo | Qué hace | Lo ejecuta |
|---|---|---|
| `../infra/glue_catalogo.tf` | Bases `retail_raw/trusted/refined`, clasificador CSV y 3 crawlers | Terraform; los crawlers los dispara el workflow |
| `hive/crear_tablas_hive.hql` | Base `retail_hive` + 5 tablas externas sobre trusted. Variable `${bucket}` | Step de EMR (`scripts/emr_ejecutar_pasos.sh`) o Hue |

## Cómo verificarlo

```bash
aws glue get-tables --database-name retail_trusted --query 'TableList[].[Name,StorageDescriptor.Location]' --output table
scripts/emr_ejecutar_pasos.sh            # step 1 = crear tablas Hive
aws glue get-tables --database-name retail_hive --query 'TableList[].Name'
```

En **Hue** (`terraform output emr_hue_url`, usuario `hadoop`): editor Hive → `SHOW DATABASES; USE retail_hive;
SHOW TABLES; DESCRIBE FORMATTED ventas;`. En **Athena**: elegir la base `retail_hive` y correr
`SELECT COUNT(*) FROM retail_hive.ventas`.

## Evidencias

| Id | Captura |
|---|---|
| E13 | Glue → Crawlers: los 3 crawlers con la última ejecución *Succeeded* y tablas creadas |
| E14 | Glue → Data Catalog → Tables → `retail_trusted.ventas`: esquema con tipos y particiones `anio`, `mes` |
| E15 | Consola EMR: clúster `retail-p2-emr` en *Waiting* y pestaña *Configurations* con `hive-site` (Glue como metastore) |
| E16 | EMR → Steps: "P5 Hive - crear tablas retail_hive" *Completed* (o Hue con `SHOW TABLES` en `retail_hive`) |
| E17 | Athena (o Glue) mostrando la base `retail_hive` creada desde Hive y una consulta sobre ella |
