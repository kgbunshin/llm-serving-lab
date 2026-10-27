# Profile: cpu (k3s on the VPS, llama.cpp) or gpu (GKE spot with L4, vLLM).
PROFILE ?= cpu
KCFG    ?= $(CURDIR)/.kube/$(PROFILE).yaml
# Always with an explicit kubeconfig: the machine's default context may be another cluster.
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

help: ## list targets
	@grep -hE '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'
	@echo "  PROFILE=$(PROFILE)  KCFG=$(KCFG)"

repos:
	$(H) repo add istio https://istio-release.storage.googleapis.com/charts --force-update >/dev/null
	$(H) repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update >/dev/null
	$(H) repo add nvidia https://helm.ngc.nvidia.com/nvidia --force-update >/dev/null
	$(H) repo update >/dev/null

# ---------- cluster: VPS (cpu profile) ----------
vps-check: ## dry run of the k3s playbook (--check --diff)
	$(ANSIBLE_PLAYBOOK) -i infra/vps/inventory.ini infra/vps/k3s.yml --check --diff
vps-up: ## install k3s on the VPS and save .kube/cpu.yaml
	$(ANSIBLE_PLAYBOOK) -i infra/vps/inventory.ini infra/vps/k3s.yml
vps-tunnel: ## SSH tunnel to the k3s API (leave it running in another terminal)
	ssh -N -L 6443:127.0.0.1:6443 $(VPS)
vps-down: ## remove k3s from the VPS (Delfos stays)
	$(ANSIBLE_PLAYBOOK) -i infra/vps/inventory.ini infra/vps/teardown.yml

# ---------- cluster: GKE (gpu profile) ----------
gke-up: ## create the GKE cluster with a spot GPU (self-destructs after TTL)
	infra/gke/up.sh
gke-down: ## delete the GKE cluster
	infra/gke/down.sh
gpu-operator: repos ## step 1: NVIDIA GPU operator (driver, device plugin, DCGM)
	$(K) create namespace gpu-operator --dry-run=client -o yaml | $(K) apply -f -
	$(K) apply -f platform/gpu/resourcequota.yaml
	$(H) upgrade --install gpu-operator nvidia/gpu-operator --version $(GPU_OP_VERSION) \
	  -n gpu-operator -f platform/gpu/gpu-operator-values.yaml --wait --timeout 20m
gpu-check: ## step 1: nvidia-smi inside a pod
	KCFG=$(KCFG) scripts/check-gpu.sh

# ---------- platform ----------
istio: repos ## step 3: Istio base + istiod + ingress gateway
	$(H) upgrade --install istio-base istio/base --version $(ISTIO_VERSION) -n istio-system --create-namespace --wait
	$(H) upgrade --install istiod istio/istiod --version $(ISTIO_VERSION) -n istio-system \
	  -f platform/istio/istiod-values.yaml --wait
	$(H) upgrade --install istio-ingressgateway istio/gateway --version $(ISTIO_VERSION) -n istio-ingress \
	  --create-namespace -f platform/istio/gateway-values.yaml --wait
	$(K) apply -f platform/istio/telemetry.yaml

monitoring: repos ## step 4: Prometheus + Grafana + rules + dashboard
	$(H) upgrade --install kps prometheus-community/kube-prometheus-stack --version $(KPS_VERSION) \
	  -n monitoring --create-namespace -f platform/monitoring/kps-values.yaml \
	  $(if $(wildcard platform/monitoring/kps-values-sso.yaml),-f platform/monitoring/kps-values-sso.yaml) --wait --timeout 10m
	$(K) apply -k platform/monitoring

platform: istio monitoring ## istio + monitoring

# ---------- app ----------
deploy: ## step 2: model for the current profile (k8s/overlays/$(PROFILE))
	$(K) apply -k k8s/overlays/$(PROFILE)
	$(K) -n llm rollout status deploy/llm --timeout=30m

smoke: ## step 2: end-to-end curl through the gateway
	KCFG=$(KCFG) scripts/smoke.sh

COST_PER_HOUR ?= $(shell python3 scripts/cost-per-hour.py $(PROFILE))
CONCURRENCY   ?= 1,2,4,8
REQUESTS      ?= 40
load: ## run the load test inside the cluster and save to results/
	$(K) create namespace loadtest --dry-run=client -o yaml | $(K) apply -f -
	$(K) -n loadtest create configmap loadgen --from-file=loadtest/loadgen.py --dry-run=client -o yaml | $(K) apply -f -
	$(K) -n loadtest delete job loadgen --ignore-not-found
	sed -e 's/value: "1,2,4,8"/value: "$(CONCURRENCY)"/' -e 's/value: "40"/value: "$(REQUESTS)"/' \
	    -e 's/value: "0"/value: "$(COST_PER_HOUR)"/' loadtest/job.yaml | $(K) apply -f -
	$(K) -n loadtest wait --for=condition=complete job/loadgen --timeout=60m
	@mkdir -p results
	$(K) -n loadtest logs job/loadgen | tee results/$(PROFILE)-$$(date +%Y%m%d-%H%M).jsonl

probe: ## enable the hourly probe (CronJob) that feeds the 24h dashboard
	$(K) create namespace loadtest --dry-run=client -o yaml | $(K) apply -f -
	$(K) -n loadtest create configmap loadgen --from-file=loadtest/loadgen.py --dry-run=client -o yaml | $(K) apply -f -
	sed -e 's/value: "0"/value: "$(COST_PER_HOUR)"/' loadtest/cronjob.yaml | $(K) apply -f -

edge: ## llm-lab Cloudflare tunnel + cloudflared in the cluster (no DNS: still unreachable)
	KCFG=$(KCFG) HOSTNAME=$(HOSTNAME) TUNNEL_NAME=$(TUNNEL_NAME) VPS=$(VPS) scripts/edge.sh

access: ## publish Grafana at $(HOSTNAME) behind Cloudflare Access (needs CF_API_TOKEN)
	KCFG=$(KCFG) HOSTNAME=$(HOSTNAME) TUNNEL_NAME=$(TUNNEL_NAME) VPS=$(VPS) KPS_VERSION=$(KPS_VERSION) scripts/access.sh

grafana: ## open Grafana on localhost:3000 (user admin)
	@echo "password: $$($(K) -n monitoring get secret kps-grafana -o jsonpath='{.data.admin-password}' | base64 -d)"
	$(K) -n monitoring port-forward svc/kps-grafana 3000:80

prometheus: ## Prometheus em localhost:9090
	$(K) -n monitoring port-forward svc/kps-kube-prometheus-stack-prometheus 9090:9090

status: ## pods for everything the project installs
	$(K) get pods -A -o wide | grep -E 'NAMESPACE|llm|istio|monitoring|gpu-operator|loadtest'

dashboard: ## regenerate platform/monitoring/dashboard.json
	python3 scripts/gen_dashboard.py

clean-app: ## remove only the model and the load test (keeps the platform)
	$(K) delete -k k8s/overlays/$(PROFILE) --ignore-not-found
	$(K) delete namespace loadtest --ignore-not-found
