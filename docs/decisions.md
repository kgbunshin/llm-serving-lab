# Decisions

A short record of what was decided and why. It becomes the backbone of the post.

## D1. Where the model runs: hybrid (VPS to build, rented GPU to measure)

The VPS that already hosts Delfos (Hostinger, 4 vCPU, 15 GB, **no GPU**) is free
at the margin, but it has no GPU. Buying a machine with a GPU doesn't fit the
budget cap. So the project has two profiles with the same manifests:

| Profile | Where | Server | What for | Cost |
|---|---|---|---|---|
| `cpu` | k3s on the Delfos VPS | llama.cpp (Q4_K_M) | all of steps 2 to 5, with no clock running | ~US$0.014/h (fixed, already paid) |
| `gpu` | Zonal GKE, 1 L4 spot node | vLLM (bf16) | step 1 and the final numbers for the post | ~US$0.35/h, only while the cluster is up |

All the Istio, Prometheus and dashboard work happens on the `cpu` profile. GKE
only comes up once the platform is ready, to run `make platform deploy load`
and shut down. That keeps GPU cost proportional to measurement hours, not to
hours spent debugging YAML.

Rejected alternatives:
- **Cloud GPU from day one:** every hour spent debugging Istio costs GPU time.
- **A remote GPU node (RunPod, Vast) joining the VPS k3s over WireGuard:** it's
  elegant, but most of these providers hand out containers, not VMs, and the
  kubelet won't run. It's a separate project.
- **EKS:** the control plane costs US$0.10/h. On GKE, one zonal cluster falls
  under the free tier.

## D2. Model: Qwen2.5-1.5B-Instruct

- Apache-2.0 license.
- Small enough to run on 4 vCPU (GGUF Q4_K_M, ~1 GB) and with room to spare on an
  L4 (bf16, ~3 GB). That leaves KV cache for concurrency, which is what vLLM exploits.
- Same model on both profiles, so the CPU vs GPU comparison in the post is fair.
- No "thinking mode", so token counts don't mix reasoning with the answer.

## D3. Server: llama.cpp on CPU, vLLM on GPU

Both expose an OpenAI-compatible API and Prometheus metrics, and the rest of the
stack doesn't change. The metrics have different names (`llamacpp:*` and
`vllm:*`), so `platform/monitoring/rules.yaml` normalizes everything into `llm:*`
and the dashboard only reads those series.

## D4. Nothing exposed to the internet

- The Istio gateway is `ClusterIP`. Access is via port-forward or from inside the cluster.
- The VPS had no firewall at all. k3s opens 6443/10250/NodePorts on 0.0.0.0, so
  the playbook creates its own nftables table that drops those ports on the
  public interface. It doesn't use `nftables.service`, because its
  `flush ruleset` would wipe out the k3s rules.
- `AuthorizationPolicy`: only the ingress gateway service account can call the model.

## D5. Latency measured at the gateway, not at the client

The "official" latency comes from `istio_request_duration_milliseconds` on the
ingress gateway, with the path as a label (`platform/istio/telemetry.yaml`). It
includes queueing and generation and excludes client network. The load test runs
as a Job inside the cluster for the same reason.

## D6. Budget cap: US$50

- GCP budget alert (`infra/gke/budget.sh`) at 50%, 80% and 100%.
- `make gke-up` schedules a `systemd --user` timer that runs `gke-down` after
  `TTL` (default 4h). A forgotten GPU shuts itself off.
- Spot on both node pools: if GCP reclaims the node, the test is rerun, which
  is cheap.
- The math: 4 sessions of 4h × US$0.35/h ≈ US$6, plus disk and egress. That
  leaves a wide margin within the US$50.

## D7. Cuts if it goes past 6 weeks

1. Step 5 (cost dashboard): cost per 1k requests comes from a manual calculation
   using the load test JSON, which already computes it.
2. AuthorizationPolicy and per-route Telemetry: the post keeps only a global p95.
