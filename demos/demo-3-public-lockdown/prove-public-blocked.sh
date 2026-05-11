#!/usr/bin/env bash
# Hit KV / Storage / AOAI from your LAPTOP using AAD tokens (no keys).
# Learning : all return 2xx
# Enforced : all return 403 NetworkSecurityPerimeterDenied
set -eu
set -o pipefail || true

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BACKEND="${BACKEND:-$HOME/workspace/tfvars/nsp-lab-backend.hcl}"

cd "$ROOT/infra/terraform/20-resources"
terraform init -reconfigure -backend-config="$BACKEND" >/dev/null
KV_URI=$(terraform output -raw kv_uri)
ST_NAME=$(terraform output -raw st_name)
AOAI_EP=$(terraform output -raw aoai_endpoint)
DEP=$(terraform output -raw aoai_model_deployment)

tok() { az account get-access-token --resource "$1" --query accessToken -o tsv; }

hit() {
  local name="$1" url="$2" token="$3" method="${4:-GET}" data="${5:-}"
  echo
  echo "── $name"
  echo "   → $method $url"
  if [[ -n "$data" ]]; then
    curl -sS -o /tmp/nsp_resp.txt -w "HTTP %{http_code}   nsp=%header{x-ms-error-code}\n" \
      -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
      -X "$method" --data "$data" "$url" || true
  else
    curl -sS -o /tmp/nsp_resp.txt -w "HTTP %{http_code}   nsp=%header{x-ms-error-code}\n" \
      -H "Authorization: Bearer $token" -X "$method" "$url" || true
  fi
  head -c 240 /tmp/nsp_resp.txt; echo
}

hit "Key Vault list secrets" \
    "${KV_URI%/}/secrets?api-version=7.4" \
    "$(tok https://vault.azure.net)"

hit "Storage list blob containers" \
    "https://${ST_NAME}.blob.core.windows.net/?comp=list" \
    "$(tok https://storage.azure.com/)"

hit "AOAI chat completions" \
    "${AOAI_EP%/}/openai/deployments/${DEP}/chat/completions?api-version=2024-08-01-preview" \
    "$(tok https://cognitiveservices.azure.com/)" \
    POST \
    '{"messages":[{"role":"user","content":"say hi in 5 words"}],"max_tokens":20}'
