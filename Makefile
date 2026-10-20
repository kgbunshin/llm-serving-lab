# Perfil: cpu (k3s na VPS, llama.cpp) ou gpu (GKE spot com L4, vLLM).
PROFILE ?= cpu
KCFG    ?= $(CURDIR)/.kube/$(PROFILE).yaml
# Sempre com kubeconfig explícito: o contexto padrão da máquina pode ser outro cluster.
K := kubectl --kubeconfig $(KCFG)
H := helm --kubeconfig $(KCFG)

ISTIO_VERSION    ?= 1.30.6
KPS_VERSION      ?= 92.10.1
GPU_OP_VERSION   ?= v26.7.2
ANSIBLE_PLAYBOOK ?= ansible-playbook
VPS              ?= root@srv1296923.hstgr.cloud
HOSTNAME         ?= llm-lab.allans.dev
TUNNEL_NAME      ?= llm-lab

.PHONY: help repos vps-check vps-up vps-tunnel vps-down gke-up gke-down gpu-operator gpu-check \
        istio monitoring platform deploy smoke load probe edge access grafana prometheus status dashboard clean-app

help: ## lista os alvos
	@grep -hE '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'
	@echo "  PROFILE=$(PROFILE)  KCFG=$(KCFG)"

repos:
	$(H) repo add istio https://istio-release.storage.googleapis.com/charts --force-update >/dev/null
	$(H) repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update >/dev/null
	$(H) repo add nvidia https://helm.ngc.nvidia.com/nvidia --force-update >/dev/null
	$(H) repo update >/dev/null

# ---------- cluster: VPS (perfil cpu) ----------
vps-check: ## dry-run do playbook do k3s (--check --diff)
	$(ANSIBLE_PLAYBOOK) -i infra/vps/inventory.ini infra/vps/k3s.yml --check --diff
vps-up: ## instala o k3s na VPS e salva .kube/cpu.yaml
	$(ANSIBLE_PLAYBOOK) -i infra/vps/inventory.ini infra/vps/k3s.yml
vps-tunnel: ## túnel SSH para a API do k3s (deixe rodando em outro terminal)
	ssh -N -L 6443:127.0.0.1:6443 $(VPS)
vps-down: ## remove o k3s da VPS (o delfos continua)
	$(ANSIBLE_PLAYBOOK) -i infra/vps/inventory.ini infra/vps/teardown.yml

# ---------- cluster: GKE (perfil gpu) ----------
gke-up: ## cria o cluster GKE com GPU spot (autodestrói após TTL)
	infra/gke/up.sh
gke-down: ## apaga o cluster GKE
	infra/gke/down.sh
gpu-operator: repos ## etapa 1: NVIDIA GPU operator (driver, device plugin, DCGM)
	$(K) create namespace gpu-operator --dry-run=client -o yaml | $(K) apply -f -
	$(K) apply -f platform/gpu/resourcequota.yaml
	$(H) upgrade --install gpu-operator nvidia/gpu-operator --version $(GPU_OP_VERSION) \
	  -n gpu-operator -f platform/gpu/gpu-operator-values.yaml --wait --timeout 20m
gpu-check: ## etapa 1: nvidia-smi dentro de um pod
	KCFG=$(KCFG) scripts/check-gpu.sh

# ---------- plataforma ----------
istio: repos ## etapa 3: Istio base + istiod + ingress gateway
	$(H) upgrade --install istio-base istio/base --version $(ISTIO_VERSION) -n istio-system --create-namespace --wait
	$(H) upgrade --install istiod istio/istiod --version $(ISTIO_VERSION) -n istio-system \
	  -f platform/istio/istiod-values.yaml --wait
	$(H) upgrade --install istio-ingressgateway istio/gateway --version $(ISTIO_VERSION) -n istio-ingress \
	  --create-namespace -f platform/istio/gateway-values.yaml --wait
	$(K) apply -f platform/istio/telemetry.yaml

monitoring: repos ## etapa 4: Prometheus + Grafana + regras + dashboard
	$(H) upgrade --install kps prometheus-community/kube-prometheus-stack --version $(KPS_VERSION) \
	  -n monitoring --create-namespace -f platform/monitoring/kps-values.yaml \
	  $(if $(wildcard platform/monitoring/kps-values-sso.yaml),-f platform/monitoring/kps-values-sso.yaml) --wait --timeout 10m
	$(K) apply -k platform/monitoring

platform: istio monitoring ## istio + monitoring

# ---------- app ----------
deploy: ## etapa 2: modelo do perfil atual (k8s/overlays/$(PROFILE))
	$(K) apply -k k8s/overlays/$(PROFILE)
	$(K) -n llm rollout status deploy/llm --timeout=30m

smoke: ## etapa 2: curl de ponta a ponta pelo gateway
	KCFG=$(KCFG) scripts/smoke.sh

COST_PER_HOUR ?= $(shell python3 scripts/cost-per-hour.py $(PROFILE))
CONCURRENCY   ?= 1,2,4,8
REQUESTS      ?= 40
load: ## roda o load test dentro do cluster e salva em results/
	$(K) create namespace loadtest --dry-run=client -o yaml | $(K) apply -f -
	$(K) -n loadtest create configmap loadgen --from-file=loadtest/loadgen.py --dry-run=client -o yaml | $(K) apply -f -
	$(K) -n loadtest delete job loadgen --ignore-not-found
	sed -e 's/value: "1,2,4,8"/value: "$(CONCURRENCY)"/' -e 's/value: "40"/value: "$(REQUESTS)"/' \
	    -e 's/value: "0"/value: "$(COST_PER_HOUR)"/' loadtest/job.yaml | $(K) apply -f -
	$(K) -n loadtest wait --for=condition=complete job/loadgen --timeout=60m
	@mkdir -p results
	$(K) -n loadtest logs job/loadgen | tee results/$(PROFILE)-$$(date +%Y%m%d-%H%M).jsonl

probe: ## liga o probe de hora em hora (CronJob) que alimenta o dashboard 24h
	$(K) create namespace loadtest --dry-run=client -o yaml | $(K) apply -f -
	$(K) -n loadtest create configmap loadgen --from-file=loadtest/loadgen.py --dry-run=client -o yaml | $(K) apply -f -
	sed -e 's/value: "0"/value: "$(COST_PER_HOUR)"/' loadtest/cronjob.yaml | $(K) apply -f -

edge: ## túnel Cloudflare llm-lab + cloudflared no cluster (sem DNS: ainda inacessível)
	KCFG=$(KCFG) HOSTNAME=$(HOSTNAME) TUNNEL_NAME=$(TUNNEL_NAME) VPS=$(VPS) scripts/edge.sh

access: ## publica o Grafana em $(HOSTNAME) atrás do Cloudflare Access (precisa CF_API_TOKEN)
	KCFG=$(KCFG) HOSTNAME=$(HOSTNAME) TUNNEL_NAME=$(TUNNEL_NAME) VPS=$(VPS) KPS_VERSION=$(KPS_VERSION) scripts/access.sh

grafana: ## abre o Grafana em localhost:3000 (usuário admin)
	@echo "senha: $$($(K) -n monitoring get secret kps-grafana -o jsonpath='{.data.admin-password}' | base64 -d)"
	$(K) -n monitoring port-forward svc/kps-grafana 3000:80

prometheus: ## Prometheus em localhost:9090
	$(K) -n monitoring port-forward svc/kps-kube-prometheus-stack-prometheus 9090:9090

status: ## pods de tudo que o projeto instala
	$(K) get pods -A -o wide | grep -E 'NAMESPACE|llm|istio|monitoring|gpu-operator|loadtest'

dashboard: ## regenera platform/monitoring/dashboard.json
	python3 scripts/gen_dashboard.py

clean-app: ## remove só o modelo e o load test (mantém plataforma)
	$(K) delete -k k8s/overlays/$(PROFILE) --ignore-not-found
	$(K) delete namespace loadtest --ignore-not-found
