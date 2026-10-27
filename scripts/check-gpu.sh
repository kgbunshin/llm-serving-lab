#!/usr/bin/env bash
# Step 1: confirms that a pod can see the GPU (nvidia-smi inside the container).
set -euo pipefail
: "${KCFG:?set KCFG}"
K="kubectl --kubeconfig $KCFG"
$K get nodes -o custom-columns='NODE:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu'
$K run gpu-check --rm -i --restart=Never --image=nvidia/cuda:12.6.3-base-ubuntu24.04 \
  --overrides='{"spec":{"tolerations":[{"key":"nvidia.com/gpu","operator":"Exists","effect":"NoSchedule"}],"containers":[{"name":"gpu-check","image":"nvidia/cuda:12.6.3-base-ubuntu24.04","command":["nvidia-smi"],"resources":{"limits":{"nvidia.com/gpu":1}}}]}}'
