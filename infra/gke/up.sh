#!/usr/bin/env bash
# Cria o cluster GKE com um nó de GPU spot e agenda a própria destruição.
set -euo pipefail
source "$(dirname "$0")/env.sh"

echo ">> cluster $CLUSTER em $ZONE (projeto $GCP_PROJECT), TTL $TTL"
gcloud container clusters create "$CLUSTER" \
  --project "$GCP_PROJECT" --zone "$ZONE" \
  --release-channel regular \
  --machine-type "$SYS_MACHINE" --spot --num-nodes 1 --disk-size 50 \
  --no-enable-managed-prometheus --logging SYSTEM

# Driver desligado no GKE: o NVIDIA GPU operator instala (etapa 1 do projeto).
gcloud container node-pools create gpu \
  --project "$GCP_PROJECT" --zone "$ZONE" --cluster "$CLUSTER" \
  --machine-type "$GPU_MACHINE" --spot --num-nodes 1 --disk-size 100 \
  --image-type UBUNTU_CONTAINERD \
  --accelerator "type=nvidia-l4,count=1,gpu-driver-version=disabled"

mkdir -p "$(dirname "$KCFG")"
KUBECONFIG="$KCFG" gcloud container clusters get-credentials "$CLUSTER" \
  --project "$GCP_PROJECT" --zone "$ZONE"
chmod 600 "$KCFG"

# Rede de segurança contra GPU esquecida: o down.sh roda sozinho depois do TTL,
# mesmo que você feche o terminal (precisa do lingering do systemd do usuário).
systemctl --user stop llm-lab-ttl.timer 2>/dev/null || true
systemd-run --user --unit llm-lab-ttl --on-active="$TTL" \
  --setenv=GCP_PROJECT="$GCP_PROJECT" --setenv=ZONE="$ZONE" --setenv=CLUSTER="$CLUSTER" \
  "$ROOT/infra/gke/down.sh"
echo ">> pronto. kubeconfig em $KCFG. Autodestruição em $TTL (systemctl --user list-timers llm-lab-ttl*)."
