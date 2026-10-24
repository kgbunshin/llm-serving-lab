# Ephemeral GPU cluster settings. Override via environment.
: "${GCP_PROJECT:?set GCP_PROJECT}"
ZONE=${ZONE:-us-central1-a}             # L4 available; check with: gcloud compute accelerator-types list --filter=nvidia-l4
CLUSTER=${CLUSTER:-llm-lab}
GPU_MACHINE=${GPU_MACHINE:-g2-standard-4} # 1x L4 24 GB, 4 vCPU, 16 GB
SYS_MACHINE=${SYS_MACHINE:-e2-standard-4} # Istio + Prometheus + Grafana
TTL=${TTL:-4h}                           # the cluster deletes itself after this
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
KCFG=${KCFG:-$ROOT/.kube/gpu.yaml}
