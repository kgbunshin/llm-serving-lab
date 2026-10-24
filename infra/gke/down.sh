#!/usr/bin/env bash
# Deletes the whole cluster (definition of done: "cluster shut down").
set -euo pipefail
source "$(dirname "$0")/env.sh"

if gcloud container clusters describe "$CLUSTER" --project "$GCP_PROJECT" --zone "$ZONE" >/dev/null 2>&1; then
  gcloud container clusters delete "$CLUSTER" --project "$GCP_PROJECT" --zone "$ZONE" --quiet
else
  echo ">> cluster $CLUSTER does not exist"
fi
systemctl --user stop llm-lab-ttl.timer 2>/dev/null || true

# Orphaned disks keep billing. There's no PVC on the GPU profile, but check anyway.
echo ">> disks left in the project (should be empty):"
gcloud compute disks list --project "$GCP_PROJECT" --filter="name~^gke-$CLUSTER" --format="table(name,zone,sizeGb)"
