#!/usr/bin/env bash
# One-time: budget alert on the billing account (US$50 by default).
# The alert doesn't shut anything down, it only emails you. The TTL does the shutting down.
set -euo pipefail
: "${BILLING_ACCOUNT:?set BILLING_ACCOUNT (gcloud billing accounts list)}"
: "${GCP_PROJECT:?set GCP_PROJECT}"
AMOUNT=${AMOUNT:-50}
gcloud billing budgets create \
  --billing-account "$BILLING_ACCOUNT" \
  --display-name "llm-serving-lab" \
  --budget-amount "${AMOUNT}USD" \
  --filter-projects "projects/$GCP_PROJECT" \
  --threshold-rule percent=0.5 --threshold-rule percent=0.8 --threshold-rule percent=1.0
