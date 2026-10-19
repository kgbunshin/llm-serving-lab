#!/usr/bin/env bash
# Apaga o cluster inteiro (critério de pronto: "cluster desligado").
set -euo pipefail
source "$(dirname "$0")/env.sh"

if gcloud container clusters describe "$CLUSTER" --project "$GCP_PROJECT" --zone "$ZONE" >/dev/null 2>&1; then
  gcloud container clusters delete "$CLUSTER" --project "$GCP_PROJECT" --zone "$ZONE" --quiet
else
  echo ">> cluster $CLUSTER não existe"
fi
systemctl --user stop llm-lab-ttl.timer 2>/dev/null || true

# Discos órfãos continuam cobrando. Não há PVC no perfil GPU, mas confira.
echo ">> discos que sobraram no projeto (deveria estar vazio):"
gcloud compute disks list --project "$GCP_PROJECT" --filter="name~^gke-$CLUSTER" --format="table(name,zone,sizeGb)"
