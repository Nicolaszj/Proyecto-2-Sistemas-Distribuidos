#!/bin/bash
# Espera a que la EC2 fuente termine de arrancar: cuando sus 13 archivos de
# ventas ya están en s3://<bucket>/raw/ec2/ventas/, el RDS también quedó cargado
# (el user_data carga el RDS ANTES de la primera sincronización).
set -euo pipefail
cd "$(dirname "$0")/../infra"
BUCKET=$(terraform output -raw bucket_datalake)
for intento in $(seq 1 40); do
  N=$(aws s3 ls "s3://${BUCKET}/raw/ec2/ventas/" 2>/dev/null | grep -c "ventas_" || true)
  echo "$(date +%H:%M:%S)  archivos de ventas en raw/ec2: ${N}/13"
  [ "$N" -ge 13 ] && { echo "FUENTES LISTAS: ya se puede correr scripts/ejecutar_pipeline.sh"; exit 0; }
  sleep 30
done
echo "Algo tarda demasiado: revisar /var/log/fuente-setup.log dentro de la EC2 fuente" >&2
exit 1
