#!/usr/bin/env bash
# Cria (se precisar) o túnel Cloudflare $TUNNEL_NAME e sobe o cloudflared no
# cluster. Sem DNS: até o `make access`, o túnel não atende hostname nenhum.
set -euo pipefail
: "${KCFG:?defina KCFG}"
VPS=${VPS:-root@srv1296923.hstgr.cloud}
HOSTNAME=${HOSTNAME:-llm-lab.allans.dev}
TUNNEL_NAME=${TUNNEL_NAME:-llm-lab}
K="kubectl --kubeconfig $KCFG"
ROOT=$(cd "$(dirname "$0")/.." && pwd)

# --config /dev/null: na VPS existe o config.yml do delfos, e sem isso alguns
# subcomandos (ex.: "tunnel info <nome>") usam o túnel do delfos e ignoram o nome.
CF="cloudflared --config /dev/null"
tunnel_id() {
  ssh "$VPS" "$CF tunnel list -o json -n $TUNNEL_NAME 2>/dev/null" \
    | python3 -c 'import sys,json; t=json.load(sys.stdin) or []; print(t[0]["id"] if t else "")'
}
TUNNEL_ID=$(tunnel_id)
if [ -z "$TUNNEL_ID" ]; then
  ssh "$VPS" "$CF tunnel create $TUNNEL_NAME"
  TUNNEL_ID=$(tunnel_id)
fi
[ -n "$TUNNEL_ID" ] || { echo "túnel $TUNNEL_NAME não encontrado" >&2; exit 1; }
echo ">> túnel $TUNNEL_NAME = $TUNNEL_ID"

$K create namespace edge --dry-run=client -o yaml | $K apply -f -
# A credencial vai direto da VPS para o Secret, sem passar pelo disco local.
ssh "$VPS" "cat /root/.cloudflared/$TUNNEL_ID.json" \
  | $K -n edge create secret generic cloudflared-creds --from-file=credentials.json=/dev/stdin \
      --dry-run=client -o yaml | $K apply -f -
sed -e "s/TUNNEL_ID/$TUNNEL_ID/" -e "s/HOSTNAME/$HOSTNAME/" "$ROOT/platform/edge/cloudflared.yaml" | $K apply -f -
$K -n edge rollout restart deploy/cloudflared
$K -n edge rollout status deploy/cloudflared --timeout=2m
