# Servindo um LLM em Kubernetes: latência, tokens e custo medidos

> Rascunho para o allans.dev. Os números entre ⟨⟩ saem de `results/*.jsonl` e do dashboard.

## O que eu queria responder

Quanto custa, de verdade, servir um modelo pequeno em Kubernetes com um mínimo de
produção (mTLS, métricas, dashboard), e onde está o gargalo.

## Setup

- Modelo: Qwen2.5-1.5B-Instruct (por quê: docs/decisions.md D2)
- CPU: k3s numa VPS de 4 vCPU, llama.cpp Q4_K_M
- GPU: GKE, 1× NVIDIA L4 spot (g2-standard-4), vLLM ⟨versão⟩
- Istio ⟨versão⟩ com mTLS STRICT, kube-prometheus-stack, Grafana

## Números

| | CPU (VPS) | GPU (L4) |
|---|---|---|
| p95 latência, concorrência 1 | ⟨⟩ s | ⟨⟩ s |
| p95 latência, concorrência 8 | ⟨⟩ s | ⟨⟩ s |
| tokens/s gerados (pico) | ⟨⟩ | ⟨⟩ |
| custo/hora | US$⟨⟩ | US$⟨⟩ |
| custo por 1k requisições | US$⟨⟩ | US$⟨⟩ |
| custo por 1M tokens | US$⟨⟩ | US$⟨⟩ |

## Onde o gargalo apareceu

⟨CPU: fila nos slots do llama.cpp (--parallel), latência cresce linear com a concorrência.⟩
⟨GPU: ...⟩

## Decisões que eu tomaria de novo (e as que não)

## Quanto custou o projeto inteiro

⟨fatura GCP⟩ + VPS que já existia.

## Cluster desligado

⟨print do `gcloud container clusters list` vazio⟩
