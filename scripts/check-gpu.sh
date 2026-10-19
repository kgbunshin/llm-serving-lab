#!/usr/bin/env bash
# Etapa 1: confirma que um pod enxerga a GPU (nvidia-smi dentro do container).
set -euo pipefail
: "${KCFG:?defina KCFG}"
K="kubectl --kubeconfig $KCFG"
$K get nodes -o custom-columns='NODE:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu'
$K run gpu-check --rm -i --restart=Never --image=nvidia/cuda:12.6.3-base-ubuntu24.04 \
  --overrides='{"spec":{"tolerations":[{"key":"nvidia.com/gpu","operator":"Exists","effect":"NoSchedule"}],"containers":[{"name":"gpu-check","image":"nvidia/cuda:12.6.3-base-ubuntu24.04","command":["nvidia-smi"],"resources":{"limits":{"nvidia.com/gpu":1}}}]}}'
