#!/bin/bash
# PUNTO 6 - Consultas SQL con EMR/Hive.
#
# Corre en el nodo master del clúster EMR como un "step" (lo envía
# scripts/emr_ejecutar_pasos.sh). Ejecuta las MISMAS 6 consultas de
# 06-consultas-sql/sql/*.sql que usan Athena y SparkSQL, cambiando ${db}
# por retail_hive (las tablas que creó 05-catalogacion/hive/crear_tablas_hive.hql).
#
# Cada resultado queda en el log del step y en:
#   s3://<bucket>/resultados/hive/<pregunta>.tsv
#
# Uso: bash ejecutar_consultas_hive.sh <bucket>
set -euo pipefail
BUCKET="$1"
TRABAJO="/tmp/consultas_hive"
rm -rf "${TRABAJO}" && mkdir -p "${TRABAJO}/resultados"

aws s3 cp "s3://${BUCKET}/scripts/06-consultas-sql/sql/" "${TRABAJO}/" --recursive --exclude "*" --include "*.sql"

for archivo in "${TRABAJO}"/p*.sql; do
  nombre=$(basename "${archivo}" .sql)
  echo "=================================================================="
  grep -m1 -- "-- P" "${archivo}"
  echo "=================================================================="
  # --hivevar db=retail_hive reemplaza ${db} dentro del .sql
  hive --hivevar db=retail_hive --hiveconf hive.cli.print.header=true -S -f "${archivo}" \
    | tee "${TRABAJO}/resultados/${nombre}.tsv"
done

aws s3 cp "${TRABAJO}/resultados/" "s3://${BUCKET}/resultados/hive/" --recursive
echo "Resultados copiados a s3://${BUCKET}/resultados/hive/"
