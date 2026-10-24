#!/usr/bin/env bash
# Creates the $TUNNEL_NAME Cloudflare tunnel (if needed) and runs cloudflared
# in the cluster. No DNS: until `make access`, the tunnel serves no hostname.
set -euo pipefail
: "${KCFG:?set KCFG}"
VPS=${VPS:-root@srv1296923.hstgr.cloud}
HOSTNAME=${HOSTNAME:-llm-lab.allans.dev}
TUNNEL_NAME=${TUNNEL_NAME:-llm-lab}
K="kubectl --kubeconfig $KCFG"
ROOT=$(cd "$(dirname "$0")/.." && pwd)

# --config /dev/null: the VPS has Delfos's config.yml, and without this some
# subcommands (e.g. "tunnel info <name>") use the Delfos tunnel and ignore the name.
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
[ -n "$TUNNEL_ID" ] || { echo "tunnel $TUNNEL_NAME not found" >&2; exit 1; }
echo ">> tunnel $TUNNEL_NAME = $TUNNEL_ID"

$K create namespace edge --dry-run=client -o yaml | $K apply -f -
# The credential goes straight from the VPS into the Secret, never touching local disk.
ssh "$VPS" "cat /root/.cloudflared/$TUNNEL_ID.json" \
  | $K -n edge create secret generic cloudflared-creds --from-file=credentials.json=/dev/stdin \
      --dry-run=client -o yaml | $K apply -f -
sed -e "s/TUNNEL_ID/$TUNNEL_ID/" -e "s/HOSTNAME/$HOSTNAME/" "$ROOT/platform/edge/cloudflared.yaml" | $K apply -f -
$K -n edge rollout restart deploy/cloudflared
$K -n edge rollout status deploy/cloudflared --timeout=2m
