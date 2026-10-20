#!/usr/bin/env bash
# Publica o Grafana em $HOSTNAME só para $ALLOWED_EMAIL.
#
# Ordem fail-closed: 1) Access app + policy, 2) Grafana confiando no JWT do
# Access, 3) só então o DNS. Se algo falhar antes do passo 3, o hostname nem
# existe.
#
# Precisa: CF_API_TOKEN com "Access: Apps and Policies = Edit" e
# "Access: Organizations = Read". Rode `make edge` antes.
set -euo pipefail
: "${CF_API_TOKEN:?defina CF_API_TOKEN}"
: "${KCFG:?defina KCFG}"
ACC=${CF_ACCOUNT_ID:-bbc57eed5d5df4203c3e1a15237387e3}
HOSTNAME=${HOSTNAME:-llm-lab.allans.dev}
TUNNEL_NAME=${TUNNEL_NAME:-llm-lab}
ALLOWED_EMAIL=${ALLOWED_EMAIL:-allan.lolzer@gmail.com}
VPS=${VPS:-root@srv1296923.hstgr.cloud}
API="https://api.cloudflare.com/client/v4/accounts/$ACC/access"
ROOT=$(cd "$(dirname "$0")/.." && pwd)

cf() { curl -sf -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" "$@"; }
jq_py() { python3 -c "import sys,json; d=json.load(sys.stdin); $1"; }

echo ">> 1/3 Access app para $HOSTNAME"
APP_JSON=$(cf "$API/apps?per_page=100" | jq_py "
apps=[a for a in d['result'] if a.get('domain')=='$HOSTNAME']
print(json.dumps(apps[0]) if apps else '')")
if [ -z "$APP_JSON" ]; then
  APP_JSON=$(cf -X POST "$API/apps" --data "{
    \"name\": \"llm-lab\", \"domain\": \"$HOSTNAME\", \"type\": \"self_hosted\",
    \"session_duration\": \"24h\", \"app_launcher_visible\": false,
    \"auto_redirect_to_identity\": false}" | jq_py "print(json.dumps(d['result']))")
fi
APP_ID=$(echo "$APP_JSON" | jq_py "print(d['id'])")
AUD=$(echo "$APP_JSON" | jq_py "print(d['aud'])")

if [ "$(cf "$API/apps/$APP_ID/policies" | jq_py "print(len(d['result']))")" = "0" ]; then
  cf -X POST "$API/apps/$APP_ID/policies" --data "{
    \"name\": \"so eu\", \"decision\": \"allow\",
    \"include\": [{\"email\": {\"email\": \"$ALLOWED_EMAIL\"}}]}" >/dev/null
fi
TEAM=$(cf "$API/organizations" | jq_py "print(d['result']['auth_domain'])")
echo "   app=$APP_ID team=$TEAM"

echo ">> 2/3 Grafana aceitando só o JWT do Access (sem formulário de login)"
VALUES=$(mktemp)
trap 'rm -f "$VALUES"' EXIT
cat > "$VALUES" <<EOF
grafana:
  grafana.ini:
    server:
      root_url: https://$HOSTNAME
    auth:
      disable_login_form: true
      disable_signout_menu: true
    auth.basic:
      enabled: false
    auth.jwt:
      enabled: true
      header_name: Cf-Access-Jwt-Assertion
      email_claim: email
      username_claim: email
      jwk_set_url: https://$TEAM/cdn-cgi/access/certs
      cache_ttl: 60m
      expect_claims: '{"aud": ["$AUD"], "iss": "https://$TEAM"}'
      auto_sign_up: true
      role_attribute_path: "email == '$ALLOWED_EMAIL' && 'Admin' || 'Viewer'"
      role_attribute_strict: true
EOF
helm --kubeconfig "$KCFG" upgrade kps prometheus-community/kube-prometheus-stack \
  --version "${KPS_VERSION:-92.10.1}" -n monitoring \
  -f "$ROOT/platform/monitoring/kps-values.yaml" -f "$VALUES" --wait >/dev/null

echo ">> 3/3 DNS $HOSTNAME -> túnel $TUNNEL_NAME"
ssh "$VPS" "cloudflared tunnel route dns $TUNNEL_NAME $HOSTNAME"

echo ">> conferindo: sem login, tem que redirecionar para o Access"
sleep 5
curl -sI "https://$HOSTNAME" | grep -iE '^(HTTP|location)' || true
