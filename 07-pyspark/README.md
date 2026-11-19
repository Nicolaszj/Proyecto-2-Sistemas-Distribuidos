# Punto 7 · Analítica descriptiva con Spark en Python (PySpark)

> **Enunciado:** realizar consultas y procesamiento analítico descriptivo con Spark en Python (pyspark).

## Qué hicimos

`analitica_pyspark.py` responde las 6 preguntas con la **API de DataFrames** de PySpark (sin SQL) y escribe la
**zona refined** (una tabla Parquet por pregunta). El mismo archivo corre en **dos motores Spark**:

| Dónde | Cómo | Para qué |
|---|---|---|
| **AWS Glue** (job `retail-p2-trusted-a-refined`) | Último job del workflow (trigger `t3`), automático | Que refined siempre esté al día para la API y el tablero |
| **Amazon EMR** (step "P7 PySpark") | `spark-submit s3://…/analitica_pyspark.py --DATALAKE s3://<bucket> --MOTOR emr` | Procesamiento en el clúster Hadoop/Spark |
| **EMR JupyterHub** (`analitica_emr.ipynb`) | Notebook con el mismo código, celda por celda | Mostrar en vivo los resultados intermedios |

### Cómo funciona

1. `ventas_enriquecidas()` une las 3 fuentes en un DataFrame:
   `ventas ⨝ clientes ⨝ paises ⨝ productos ⨝ tasas_cambio` y calcula `importe_usd = importe_gbp × gbp_usd`.
   Se deja en caché (`.cache()`) porque las 6 preguntas lo reutilizan.
2. Una función por pregunta (`p1_top_paises_ingreso_usd`, …, `p6_ventas_dia_hora`) con `groupBy`, `agg`,
   `countDistinct`, `when`, `orderBy`, `limit`, `create_map`…
3. `main()` recorre la lista `PREGUNTAS`, guarda cada resultado en `refined/<nombre de la función>/` y lo imprime.

| Función | Salida en refined | Columnas |
|---|---|---|
| `p1_top_paises_ingreso_usd` | `refined/p1_top_paises_ingreso_usd/` | pais, ingreso_neto_usd, ingreso_neto_gbp, clientes |
| `p2_ingreso_mensual` | `refined/p2_ingreso_mensual/` | anio, mes, ingreso_neto_gbp, ingreso_neto_usd, facturas, ticket_promedio_gbp, periodo |
| `p3_top_productos` | `refined/p3_top_productos/` | codigo_producto, descripcion, unidades_netas, ingreso_neto_gbp, ingreso_neto_usd |
| `p4_gasto_por_habitante` | `refined/p4_gasto_por_habitante/` | pais, poblacion, pib_per_capita_usd, ingreso_neto_usd, usd_por_mil_habitantes |
| `p5_devoluciones_por_region` | `refined/p5_devoluciones_por_region/` | region_comercial, ventas_brutas_gbp, devoluciones_gbp, tasa_devolucion_pct, facturas_devueltas |
| `p6_ventas_dia_hora` | `refined/p6_ventas_dia_hora/` | dia_semana, dia, hora, facturas, ingreso_bruto_gbp |

El crawler refined cataloga estas 6 carpetas en `retail_refined`, que es lo que consulta la API (punto 8).

## Archivos

| Archivo | Qué hace |
|---|---|
| `analitica_pyspark.py` | Script principal (Glue y EMR) |
| `analitica_emr.ipynb` | Notebook para JupyterHub del EMR (kernel PySpark): mismo código, celda por celda |

## Cómo verificarlo

- Glue: **ETL jobs → retail-p2-trusted-a-refined → Runs** (*Succeeded*); en los logs se ven las 6 tablas.
- EMR: `scripts/emr_ejecutar_pasos.sh` → step "P7 PySpark - analitica refined" → *stdout*.
- JupyterHub: `terraform output emr_jupyterhub_url` → usuario `jovyan`, clave `jupyter` → *Upload*
  `analitica_emr.ipynb` → kernel **PySpark** → escribir el bucket en la primera celda → *Run All*.
- Local (sin AWS): `spark-submit analitica_pyspark.py --DATALAKE file:///ruta/datalake`.

## Evidencias

| Id | Captura |
|---|---|
| E22 | Glue → `retail-p2-trusted-a-refined` *Succeeded* (o su log con las tablas impresas) |
| E23 | EMR: stdout del step "P7 PySpark" o el notebook en JupyterHub con resultados |
| E24 | S3 `refined/` con las 6 carpetas y Glue → tablas de `retail_refined` |
