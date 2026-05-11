#!/usr/bin/env bash
# Same calls as prove-public-blocked.sh but executed ON the jump VM.
# Should ALWAYS succeed because the source IP is in the subscription, matching the default profile.
set -eu
set -o pipefail || true

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BACKEND="${BACKEND:-$HOME/workspace/tfvars/nsp-lab-backend.hcl}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/nsp_lab_ed25519}"

cd "$ROOT/infra/terraform/10-perimeter"
terraform init -reconfigure -backend-config="$BACKEND" >/dev/null
IP=$(terraform output -raw jump_public_ip)
UAMI_CLIENT_ID=$(terraform output -raw uami_client_id)

cd "$ROOT/infra/terraform/20-resources"
terraform init -reconfigure -backend-config="$BACKEND" >/dev/null
KV_URI=$(terraform output -raw kv_uri)
ST_NAME=$(terraform output -raw st_name)
AOAI_EP=$(terraform output -raw aoai_endpoint)
DEP=$(terraform output -raw aoai_model_deployment)

echo "→ running on jump VM @ $IP"
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" "labadmin@$IP" \
  KV_URI="$KV_URI" ST_NAME="$ST_NAME" AOAI_EP="$AOAI_EP" DEP="$DEP" UAMI_CLIENT_ID="$UAMI_CLIENT_ID" \
  'bash -s' <<'REMOTE'
set -e
imds() {
  curl -s -H "Metadata: true" \
    "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=$1&client_id=$UAMI_CLIENT_ID" \
    | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])'
}

hit() {
  local name="$1" url="$2" tok="$3" method="${4:-GET}" data="${5:-}"
  echo
  echo "── $name"
  echo "   → $method $url"
  if [[ -n "$data" ]]; then
    curl -sS -o /tmp/r.txt -w "HTTP %{http_code}   nsp=%header{x-ms-error-code}\n" \
      -H "Authorization: Bearer $tok" -H "Content-Type: application/json" \
      -X "$method" --data "$data" "$url" || true
  else
    curl -sS -o /tmp/r.txt -w "HTTP %{http_code}   nsp=%header{x-ms-error-code}\n" \
      -H "Authorization: Bearer $tok" -X "$method" "$url" || true
  fi
  head -c 240 /tmp/r.txt; echo
}

hit "KV list secrets"      "${KV_URI%/}/secrets?api-version=7.4"                   "$(imds https://vault.azure.net)"
hit "Storage list blobs"   "https://${ST_NAME}.blob.core.windows.net/?comp=list"   "$(imds https://storage.azure.com/)"
hit "AOAI chat completions" \
    "${AOAI_EP%/}/openai/deployments/${DEP}/chat/completions?api-version=2024-08-01-preview" \
    "$(imds https://cognitiveservices.azure.com/)" \
    POST '{"messages":[{"role":"user","content":"say hi in 5 words"}],"max_tokens":20}'
REMOTE
