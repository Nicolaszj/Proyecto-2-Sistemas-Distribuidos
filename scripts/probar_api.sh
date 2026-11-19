#!/bin/bash
# PUNTO 8 - Prueba la API de API Gateway desde la terminal.
set -euo pipefail
cd "$(dirname "$0")/../infra"
API=$(terraform output -raw api_url)
echo "GET ${API}/salud";      curl -s "${API}/salud"; echo; echo
echo "GET ${API}/preguntas";  curl -s "${API}/preguntas" | python3 -m json.tool | head -20; echo
for p in p1 p2 p3 p4 p5 p6; do
  echo "GET ${API}/preguntas/${p}"
  curl -s "${API}/preguntas/${p}" | python3 -c "
import json, sys
d = json.load(sys.stdin)
if 'error' in d: print('  ERROR:', d['error']); sys.exit()
print('  ', d['pregunta']); print('   athena:', d['athena_query_id'], d['tiempo_ms'], 'ms')
for f in d['filas'][:3]: print('   ', f)
"
done
