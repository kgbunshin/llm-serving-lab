#!/usr/bin/env bash
# Etapa 2: uma requisição de ponta a ponta pelo gateway (port-forward local).
set -euo pipefail
: "${KCFG:?defina KCFG (kubeconfig do perfil)}"
PORT=${PORT:-18080}

kubectl --kubeconfig "$KCFG" -n istio-ingress port-forward svc/istio-ingressgateway "$PORT:80" >/dev/null &
pf=$!
trap 'kill $pf 2>/dev/null' EXIT
for _ in $(seq 20); do curl -s "localhost:$PORT/health" >/dev/null && break; sleep 0.5; done

echo "--- /v1/models"
curl -sf "localhost:$PORT/v1/models"; echo
echo "--- /v1/chat/completions"
time curl -sf "localhost:$PORT/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen2.5-1.5b","max_tokens":64,"messages":[{"role":"user","content":"Diga oi em uma frase."}]}'
echo
