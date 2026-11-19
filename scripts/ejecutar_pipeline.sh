#!/bin/bash
# PUNTO 3 - Lanza a mano el workflow de Glue (el mismo que corre solo cada día)
# y muestra el avance hasta que termina: ingesta -> raw -> trusted -> refined.
set -euo pipefail
cd "$(dirname "$0")/../infra"
WF=$(terraform output -raw glue_workflow)
RUN=$(aws glue start-workflow-run --name "$WF" --query RunId --output text)
echo "Workflow ${WF} iniciado. RunId: ${RUN}"
while true; do
  ESTADO=$(aws glue get-workflow-run --name "$WF" --run-id "$RUN" --query 'Run.Status' --output text)
  aws glue get-workflow-run --name "$WF" --run-id "$RUN" \
    --query 'Run.Statistics.[TotalActions,RunningActions,SucceededActions,FailedActions]' \
    --output text | awk -v t="$(date +%H:%M:%S)" -v e="$ESTADO" '{print t"  estado="e"  pasos="$1"  corriendo="$2"  exitosos="$3"  fallidos="$4}'
  [ "$ESTADO" = "COMPLETED" ] || [ "$ESTADO" = "ERROR" ] || [ "$ESTADO" = "STOPPED" ] && break
  sleep 30
done
echo; echo "Detalle de cada paso:"
aws glue get-workflow-run --name "$WF" --run-id "$RUN" --include-graph \
  --query 'Run.Graph.Nodes[].{Paso:Name,Tipo:Type,Job:JobDetails.JobRuns[0].JobRunState,Crawler:CrawlerDetails.Crawls[0].State}' \
  --output table
FALLIDAS=$(aws glue get-workflow-run --name "$WF" --run-id "$RUN" --query 'Run.Statistics.FailedActions' --output text)
[ "$FALLIDAS" = "0" ] && echo "PIPELINE OK: raw, trusted y refined actualizados y catalogados." \
  || { echo "Hubo ${FALLIDAS} pasos fallidos: ver Glue > ETL jobs > Runs > Error" >&2; exit 1; }
