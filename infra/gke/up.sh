#!/usr/bin/env bash
# Creates the GKE cluster with a spot GPU node and schedules its own destruction.
set -euo pipefail
source "$(dirname "$0")/env.sh"

echo ">> cluster $CLUSTER in $ZONE (project $GCP_PROJECT), TTL $TTL"
gcloud container clusters create "$CLUSTER" \
  --project "$GCP_PROJECT" --zone "$ZONE" \
  --release-channel regular \
  --machine-type "$SYS_MACHINE" --spot --num-nodes 1 --disk-size 50 \
  --no-enable-managed-prometheus --logging SYSTEM

# Driver disabled on GKE: the NVIDIA GPU operator installs it (step 1 of the project).
gcloud container node-pools create gpu \
  --project "$GCP_PROJECT" --zone "$ZONE" --cluster "$CLUSTER" \
  --machine-type "$GPU_MACHINE" --spot --num-nodes 1 --disk-size 100 \
  --image-type UBUNTU_CONTAINERD \
  --accelerator "type=nvidia-l4,count=1,gpu-driver-version=disabled"

mkdir -p "$(dirname "$KCFG")"
KUBECONFIG="$KCFG" gcloud container clusters get-credentials "$CLUSTER" \
  --project "$GCP_PROJECT" --zone "$ZONE"
chmod 600 "$KCFG"

# Safety net against a forgotten GPU: down.sh runs on its own after the TTL,
# even if you close the terminal (requires systemd user lingering).
systemctl --user stop llm-lab-ttl.timer 2>/dev/null || true
systemd-run --user --unit llm-lab-ttl --on-active="$TTL" \
  --setenv=GCP_PROJECT="$GCP_PROJECT" --setenv=ZONE="$ZONE" --setenv=CLUSTER="$CLUSTER" \
  "$ROOT/infra/gke/down.sh"
echo ">> done. kubeconfig at $KCFG. Self-destruct in $TTL (systemctl --user list-timers llm-lab-ttl*)."
