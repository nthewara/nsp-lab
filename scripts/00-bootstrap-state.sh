#!/usr/bin/env bash
# Bootstrap: create an ISOLATED tfstate storage account just for nsp-lab.
# Idempotent — re-running is safe.
set -eu
set -o pipefail || true

SUB="${ARM_SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}"
LOC="${LOCATION:-australiaeast}"
RG="tfstate-nsp-lab"
CONTAINER="tfstate"

az account set --subscription "$SUB"

if ! az group show -n "$RG" -o none 2>/dev/null; then
  echo "→ creating RG $RG in $LOC"
  az group create -n "$RG" -l "$LOC" --tags lab=nsp-lab purpose=tfstate -o none
else
  echo "✓ RG $RG exists"
fi

ACCOUNT="$(az storage account list -g "$RG" --query "[?starts_with(name,'tfstatensplab')].name | [0]" -o tsv)"
if [[ -z "$ACCOUNT" ]]; then
  SUFFIX=$(LC_ALL=C head -c 200 /dev/urandom | tr -dc 'a-z0-9' | head -c 6)
  [ -z "$SUFFIX" ] && SUFFIX="$(date +%s | tail -c 7)"
  ACCOUNT="tfstatensplab${SUFFIX}"
  echo "→ creating storage account $ACCOUNT"
  az storage account create \
    -g "$RG" -n "$ACCOUNT" -l "$LOC" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --allow-blob-public-access false \
    --min-tls-version TLS1_2 \
    -o none
else
  echo "✓ storage account $ACCOUNT exists"
fi

echo "→ ensuring container '$CONTAINER' exists (using Entra auth)"
az storage container create \
  --account-name "$ACCOUNT" \
  --name "$CONTAINER" \
  --auth-mode login \
  -o none

BACKEND_HCL="$HOME/workspace/tfvars/nsp-lab-backend.hcl"
mkdir -p "$(dirname "$BACKEND_HCL")"
cat > "$BACKEND_HCL" <<EOF
resource_group_name  = "$RG"
storage_account_name = "$ACCOUNT"
container_name       = "$CONTAINER"
use_azuread_auth     = true
subscription_id      = "$SUB"
EOF

echo
echo "✔ Bootstrap done."
echo "  backend.hcl  : $BACKEND_HCL"
echo "  RG           : $RG"
echo "  Account      : $ACCOUNT"
echo "  Container    : $CONTAINER"
echo
echo "Next: ./scripts/10-deploy.sh"
