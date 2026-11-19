#!/bin/bash
# Evidencias rápidas del datalake: archivos por zona y tablas del catálogo.
set -uo pipefail
cd "$(dirname "$0")/../infra"
BUCKET=$(terraform output -raw bucket_datalake)
echo "== Archivos por zona en s3://${BUCKET} =="
for zona in raw/rds raw/ec2 raw/url trusted refined; do
  aws s3 ls "s3://${BUCKET}/${zona}/" --recursive --summarize \
    | awk -v z="$zona" '/Total Objects/{o=$3} /Total Size/{s=$3} END{printf "  %-10s %5d objetos  %8.1f MB\n", z, o, s/1048576}'
done
echo; echo "== Tablas del Glue Data Catalog =="
for db in retail_raw retail_trusted retail_refined retail_hive; do
  echo "  ${db}: $(aws glue get-tables --database-name "$db" --query 'TableList[].Name' --output text 2>/dev/null || echo '(no existe aún)')"
done
echo; echo "== Reporte de calidad de la preparación (punto 4) =="
aws s3 cp "s3://${BUCKET}/trusted/_reportes/calidad_ventas.json" - 2>/dev/null || echo "  (aún no se ha corrido el pipeline)"
