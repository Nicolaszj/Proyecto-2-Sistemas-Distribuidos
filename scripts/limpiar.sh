#!/bin/bash
# Borra TODO lo del proyecto en AWS (después de sustentar).
#   1. La base retail_hive (la creó Hive en EMR, Terraform no la conoce).
#   2. terraform destroy: bucket con su contenido, RDS, EC2, Glue, Athena, EMR, API.
set -euo pipefail
cd "$(dirname "$0")/../infra"
read -r -p "Esto borra todo el proyecto en AWS. Escriba BORRAR para seguir: " OK
[ "$OK" = "BORRAR" ] || { echo "Cancelado."; exit 0; }
aws glue delete-database --name retail_hive 2>/dev/null && echo "retail_hive borrada" || echo "retail_hive no existía"
terraform destroy -auto-approve
echo "Listo. Revisar en la consola que no quede ningún EMR en estado Waiting/Running."
