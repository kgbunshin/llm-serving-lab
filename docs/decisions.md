# Decisões

Registro curto do que foi decidido e por quê. Vira a espinha do post.

## D1. Onde o modelo roda: híbrido (VPS para construir, GPU alugada para medir)

A VPS que já hospeda o delfos (Hostinger, 4 vCPU, 15 GB, **sem GPU**) é de graça
na margem, mas não tem GPU. Comprar uma máquina com GPU não cabe no teto. Por
isso o projeto tem dois perfis com os mesmos manifests:

| Perfil | Onde | Servidor | Para quê | Custo |
|---|---|---|---|---|
| `cpu` | k3s na VPS do delfos | llama.cpp (Q4_K_M) | etapas 2 a 5 inteiras, sem relógio correndo | ~US$0,014/h (fixo, já pago) |
| `gpu` | GKE zonal, 1 nó L4 spot | vLLM (bf16) | etapa 1 e números finais do post | ~US$0,35/h só com o cluster ligado |

Todo o trabalho de Istio, Prometheus e dashboard é feito no perfil `cpu`. O GKE
só liga quando a plataforma já está pronta, para rodar `make platform deploy load`
e desligar. Isso deixa o custo da GPU proporcional às horas de medição, não às
horas de depuração de YAML.

Alternativas descartadas:
- **GPU só na nuvem desde o início:** cada hora depurando Istio custa GPU.
- **Nó de GPU remoto entrando no k3s da VPS (RunPod, Vast) via WireGuard:** é
  bonito, mas a maioria desses provedores entrega container e não VM, e o
  kubelet não roda. É um projeto à parte.
- **EKS:** o control plane cobra US$0,10/h. No GKE, um cluster zonal entra no
  free tier.

## D2. Modelo: Qwen2.5-1.5B-Instruct

- Licença Apache-2.0.
- Pequeno o bastante para rodar em 4 vCPU (GGUF Q4_K_M, ~1 GB) e com sobra numa
  L4 (bf16, ~3 GB). Sobra KV cache para concorrência, que é o que o vLLM explora.
- O mesmo modelo nos dois perfis: a comparação CPU vs GPU no post fica justa.
- Sem "thinking mode", então a contagem de tokens não mistura raciocínio com resposta.

## D3. Servidor: llama.cpp na CPU, vLLM na GPU

Os dois expõem API OpenAI-compatível e métricas Prometheus, e o resto da stack
não muda. As métricas têm nomes diferentes (`llamacpp:*` e `vllm:*`), então
`platform/monitoring/rules.yaml` normaliza tudo em `llm:*` e o dashboard só lê
essas séries.

## D4. Nada exposto na internet

- O gateway do Istio é `ClusterIP`. O acesso é por port-forward ou de dentro do cluster.
- A VPS não tinha firewall nenhum. O k3s abre 6443/10250/NodePorts em 0.0.0.0,
  então o playbook cria uma tabela nftables própria que descarta essas portas
  na interface pública. Não usa `nftables.service`, porque o `flush ruleset`
  dele apagaria as regras do k3s.
- `AuthorizationPolicy`: só o service account do ingress gateway chama o modelo.

## D5. Latência medida no gateway, não no cliente

A latência "oficial" vem de `istio_request_duration_milliseconds` no ingress
gateway, com o path como label (`platform/istio/telemetry.yaml`). Inclui fila e
geração, exclui rede do cliente. O load test roda como Job dentro do cluster
pelo mesmo motivo.

## D6. Teto de custo: US$50

- Alerta de orçamento no GCP (`infra/gke/budget.sh`) em 50%, 80% e 100%.
- O `make gke-up` agenda um timer `systemd --user` que roda `gke-down` depois de
  `TTL` (padrão 4h). GPU esquecida se apaga sozinha.
- Spot nos dois node pools: se a GCP tomar o nó de volta, o teste é refeito,
  o que é barato.
- Conta: 4 sessões de 4h × US$0,35/h ≈ US$6, mais disco e egress. Sobra
  margem grande dentro dos US$50.

## D7. Cortes se passar de 6 semanas

1. Etapa 5 (dashboard de custo): o custo por 1k requisições sai da conta manual
   com o JSON do load test, que já calcula.
2. AuthorizationPolicy e Telemetry por rota: o post fica só com p95 global.
