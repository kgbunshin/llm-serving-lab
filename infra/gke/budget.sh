#!/usr/bin/env bash
# Uma vez só: alerta de orçamento no billing account (US$50 por padrão).
# Alerta não desliga nada sozinho, só avisa por e-mail. Quem desliga é o TTL.
set -euo pipefail
: "${BILLING_ACCOUNT:?defina BILLING_ACCOUNT (gcloud billing accounts list)}"
: "${GCP_PROJECT:?defina GCP_PROJECT}"
AMOUNT=${AMOUNT:-50}
gcloud billing budgets create \
  --billing-account "$BILLING_ACCOUNT" \
  --display-name "llm-serving-lab" \
  --budget-amount "${AMOUNT}USD" \
  --filter-projects "projects/$GCP_PROJECT" \
  --threshold-rule percent=0.5 --threshold-rule percent=0.8 --threshold-rule percent=1.0
