#!/bin/bash
# PUNTOS 5, 6 y 7 en EMR: envía 4 "steps" al clúster y espera a que terminen.
#   1. Hive: crea retail_hive (tablas externas sobre trusted)        -> punto 5
#   2. Hive: corre las 6 consultas SQL sobre retail_hive             -> punto 6
#   3. SparkSQL: corre las mismas 6 consultas sobre retail_trusted   -> punto 6
#   4. PySpark: analitica_pyspark.py regenera refined desde EMR      -> punto 7
# Requisitos: crear_emr = true aplicado y el pipeline de Glue ya corrido.
set -euo pipefail
cd "$(dirname "$0")/../infra"
CID=$(terraform output -raw emr_cluster_id)
BUCKET=$(terraform output -raw bucket_datalake)
[ -n "$CID" ] || { echo "No hay clúster: poner crear_emr = true y hacer terraform apply" >&2; exit 1; }
S3="s3://${BUCKET}/scripts"

echo "Esperando a que el clúster ${CID} esté listo (WAITING)..."
aws emr wait cluster-running --cluster-id "$CID"

PASOS=$(cat <<JSON
[
  {"Type":"CUSTOM_JAR","Name":"P5 Hive - crear tablas retail_hive","ActionOnFailure":"CONTINUE","Jar":"command-runner.jar",
   "Args":["hive-script","--run-hive-script","--args","-f","${S3}/05-catalogacion/hive/crear_tablas_hive.hql","-d","bucket=${BUCKET}"]},
  {"Type":"CUSTOM_JAR","Name":"P6 Hive - 6 consultas SQL","ActionOnFailure":"CONTINUE","Jar":"command-runner.jar",
   "Args":["bash","-c","aws s3 cp ${S3}/06-consultas-sql/hive/ejecutar_consultas_hive.sh /tmp/ && bash /tmp/ejecutar_consultas_hive.sh ${BUCKET}"]},
  {"Type":"CUSTOM_JAR","Name":"P6 SparkSQL - 6 consultas SQL","ActionOnFailure":"CONTINUE","Jar":"command-runner.jar",
   "Args":["spark-submit","--deploy-mode","client","${S3}/06-consultas-sql/sparksql/consultas_sparksql.py","--DATALAKE","s3://${BUCKET}"]},
  {"Type":"CUSTOM_JAR","Name":"P7 PySpark - analitica refined","ActionOnFailure":"CONTINUE","Jar":"command-runner.jar",
   "Args":["spark-submit","--deploy-mode","client","${S3}/07-pyspark/analitica_pyspark.py","--DATALAKE","s3://${BUCKET}","--MOTOR","emr"]}
]
JSON
)
IDS=$(aws emr add-steps --cluster-id "$CID" --steps "$PASOS" --query 'StepIds' --output text)
echo "Steps enviados: ${IDS}"
for ID in $IDS; do
  aws emr wait step-complete --cluster-id "$CID" --step-id "$ID" 2>/dev/null || true
done
aws emr list-steps --cluster-id "$CID" --step-ids $IDS \
  --query 'Steps[].{Paso:Name,Estado:Status.State,Id:Id}' --output table
echo "Salida de cada step: consola EMR > clúster > Steps > View logs (stdout),"
echo "o en s3://${BUCKET}/resultados/hive/ y s3://${BUCKET}/resultados/sparksql/"
