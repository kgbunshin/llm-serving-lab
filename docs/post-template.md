# Serving an LLM on Kubernetes: latency, tokens and cost, measured

> Draft for allans.dev. Numbers in ⟨⟩ come from `results/*.jsonl` and the dashboard.

## What I wanted to answer

How much it really costs to serve a small model on Kubernetes with a minimum of
production readiness (mTLS, metrics, dashboard), and where the bottleneck is.

## Setup

- Model: Qwen2.5-1.5B-Instruct (why: docs/decisions.md D2)
- CPU: k3s on a 4 vCPU VPS, llama.cpp Q4_K_M
- GPU: GKE, 1× NVIDIA L4 spot (g2-standard-4), vLLM ⟨version⟩
- Istio ⟨version⟩ with mTLS STRICT, kube-prometheus-stack, Grafana

## Numbers

| | CPU (VPS) | GPU (L4) |
|---|---|---|
| p95 latency, concurrency 1 | ⟨⟩ s | ⟨⟩ s |
| p95 latency, concurrency 8 | ⟨⟩ s | ⟨⟩ s |
| generated tokens/s (peak) | ⟨⟩ | ⟨⟩ |
| cost/hour | US$⟨⟩ | US$⟨⟩ |
| cost per 1k requests | US$⟨⟩ | US$⟨⟩ |
| cost per 1M tokens | US$⟨⟩ | US$⟨⟩ |

## Where the bottleneck showed up

⟨CPU: queueing on llama.cpp slots (--parallel), latency grows linearly with concurrency.⟩
⟨GPU: ...⟩

## Decisions I'd make again (and the ones I wouldn't)

## What the whole project cost

⟨GCP bill⟩ + the VPS that already existed.

## Cluster shut down

⟨screenshot of an empty `gcloud container clusters list`⟩
