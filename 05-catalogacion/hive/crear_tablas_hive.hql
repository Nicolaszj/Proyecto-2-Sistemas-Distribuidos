-- PUNTO 5 - Catalogación con EMR/Hive.
--
-- Crea la base retail_hive con tablas EXTERNAS que apuntan a la zona trusted.
-- "Externa" = Hive solo guarda el esquema; los datos se quedan en S3 y borrar
-- la tabla NO borra los archivos.
--
-- El clúster EMR usa el AWS Glue Data Catalog como metastore de Hive
-- (infra/emr.tf, clasificación hive-site). Por eso estas tablas, creadas desde
-- Hive, aparecen también en la consola de Glue y se pueden consultar en Athena.
--
-- Variable: ${bucket} (nombre del bucket del datalake).
--   Step EMR: hive-script --run-hive-script --args -f s3://.../crear_tablas_hive.hql -d bucket=<bucket>
--   Hue:      al pegar el script, Hue muestra una casilla "bucket" para escribirlo.

CREATE DATABASE IF NOT EXISTS retail_hive
  COMMENT 'Tablas Hive sobre la zona trusted del datalake (Proyecto 2)'
  LOCATION 's3://${bucket}/hive/retail_hive/';

USE retail_hive;

-- Ventas limpias (origen: archivos de la EC2). Particionada por año y mes.
DROP TABLE IF EXISTS ventas;
CREATE EXTERNAL TABLE ventas (
  factura             STRING  COMMENT 'Número de factura (si empieza por C es devolución)',
  codigo_producto     STRING,
  cantidad            INT     COMMENT 'Negativa en devoluciones',
  precio_unitario_gbp DOUBLE,
  importe_gbp         DOUBLE  COMMENT 'cantidad * precio_unitario_gbp',
  id_cliente          INT,
  fecha_hora          TIMESTAMP,
  fecha               DATE,
  hora                INT,
  dia_semana          INT     COMMENT '1 = lunes ... 7 = domingo',
  es_devolucion       BOOLEAN
)
PARTITIONED BY (anio INT, mes INT)
STORED AS PARQUET
LOCATION 's3://${bucket}/trusted/ventas/';

-- Registra las carpetas anio=AAAA/mes=M que ya existen en S3 como particiones.
MSCK REPAIR TABLE ventas;

-- Clientes (origen: RDS MariaDB).
DROP TABLE IF EXISTS clientes;
CREATE EXTERNAL TABLE clientes (
  id_cliente INT,
  pais       STRING
)
STORED AS PARQUET
LOCATION 's3://${bucket}/trusted/clientes/';

-- Productos (origen: RDS MariaDB).
DROP TABLE IF EXISTS productos;
CREATE EXTERNAL TABLE productos (
  codigo_producto STRING,
  descripcion     STRING
)
STORED AS PARQUET
LOCATION 's3://${bucket}/trusted/productos/';

-- Países (origen: RDS MariaDB + Banco Mundial por URL).
DROP TABLE IF EXISTS paises;
CREATE EXTERNAL TABLE paises (
  pais               STRING,
  iso3               STRING,
  region_comercial   STRING,
  poblacion          BIGINT,
  pib_per_capita_usd DOUBLE
)
STORED AS PARQUET
LOCATION 's3://${bucket}/trusted/paises/';

-- Tasas de cambio diarias (origen: API Frankfurter por URL).
DROP TABLE IF EXISTS tasas_cambio;
CREATE EXTERNAL TABLE tasas_cambio (
  fecha             DATE,
  gbp_usd           DOUBLE,
  gbp_eur           DOUBLE,
  es_tasa_publicada BOOLEAN COMMENT 'false = día sin publicación, se usó la última tasa'
)
STORED AS PARQUET
LOCATION 's3://${bucket}/trusted/tasas_cambio/';

SHOW TABLES;
SELECT COUNT(*) AS lineas_de_venta FROM ventas;
