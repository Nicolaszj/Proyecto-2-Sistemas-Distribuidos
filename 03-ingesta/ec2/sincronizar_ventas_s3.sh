#!/bin/bash
# PUNTO 3 - Ingesta automática: archivos de la EC2  ->  S3 zona raw.
#
# Corre DENTRO de la EC2 "fuente de archivos". El user_data de la instancia
# (infra/plantillas/fuente_ec2_user_data.sh.tftpl) lo copia a /opt/fuente/ y
# lo programa en cron cada 10 minutos (/etc/cron.d/sincronizar-ventas).
#
# "aws s3 sync" solo sube lo que es nuevo o cambió, así que si el sistema de
# caja deja un archivo nuevo en /srv/ventas, en máximo 10 minutos está en:
#   s3://<bucket>/raw/ec2/ventas/ventas_AAAA_MM.csv
#
# Permisos: la EC2 usa el perfil LabInstanceProfile (rol LabRole), que puede
# escribir en S3. No hay llaves guardadas en la máquina.
set -euo pipefail

source /opt/fuente/config.env            # define BUCKET (lo escribe el user_data)
ORIGEN="/srv/ventas"
DESTINO="s3://${BUCKET}/raw/ec2/ventas/"

echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') sincronizando ${ORIGEN} -> ${DESTINO}"
aws s3 sync "${ORIGEN}" "${DESTINO}" --exclude "*" --include "ventas_*.csv" --only-show-errors
echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') listo: $(ls ${ORIGEN}/ventas_*.csv | wc -l) archivos en origen"
