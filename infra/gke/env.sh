# Configuração do cluster GPU efêmero. Sobrescreva via ambiente.
: "${GCP_PROJECT:?defina GCP_PROJECT}"
ZONE=${ZONE:-us-central1-a}             # L4 disponível; confira com: gcloud compute accelerator-types list --filter=nvidia-l4
CLUSTER=${CLUSTER:-llm-lab}
GPU_MACHINE=${GPU_MACHINE:-g2-standard-4} # 1x L4 24 GB, 4 vCPU, 16 GB
SYS_MACHINE=${SYS_MACHINE:-e2-standard-4} # Istio + Prometheus + Grafana
TTL=${TTL:-4h}                           # o cluster se apaga sozinho depois disso
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
KCFG=${KCFG:-$ROOT/.kube/gpu.yaml}
