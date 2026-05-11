#!/usr/bin/env bash
# Flip every association on nsp-lab-perimeter to Enforced.
# Async: poll until each association reports Enforced + Succeeded.
set -eu
set -o pipefail || true
TARGET_MODE="${TARGET_MODE:-Enforced}"

SUB="${SUB:-$(az account show --query id -o tsv)}"
RG="$(az group list --query "[?starts_with(name,'rg-nsp-lab-')].name | [0]" -o tsv --subscription "$SUB")"
NSP="$(az network perimeter list -g "$RG" --query '[0].name' -o tsv --subscription "$SUB")"
[[ -z "$NSP" ]] && { echo "no NSP found in $RG"; exit 1; }
echo "→ flipping all associations in $NSP (RG=$RG) to $TARGET_MODE"

mapfile -t ASSOCS < <(az network perimeter association list --perimeter-name "$NSP" -g "$RG" --subscription "$SUB" --query '[].name' -o tsv)
echo "found ${#ASSOCS[@]} associations: ${ASSOCS[*]}"

API="2024-07-01"
for a in "${ASSOCS[@]}"; do
  ID="/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Network/networkSecurityPerimeters/$NSP/resourceAssociations/$a"
  CUR=$(az resource show --ids "$ID" --api-version "$API" --query 'properties.accessMode' -o tsv 2>/dev/null || echo "?")
  PROFILE=$(az resource show --ids "$ID" --api-version "$API" --query 'properties.profile.id' -o tsv)
  TARGET_RES=$(az resource show --ids "$ID" --api-version "$API" --query 'properties.privateLinkResource.id' -o tsv)
  echo "  $a: $CUR → $TARGET_MODE"
  az resource update --ids "$ID" --api-version "$API" \
    --set "properties.accessMode=$TARGET_MODE" "properties.profile.id=$PROFILE" "properties.privateLinkResource.id=$TARGET_RES" \
    --output none
done

echo "→ polling for propagation (up to 5 min)"
END=$(( $(date +%s) + 300 ))
while [[ $(date +%s) -lt $END ]]; do
  ALL_GOOD=1
  for a in "${ASSOCS[@]}"; do
    ID="/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Network/networkSecurityPerimeters/$NSP/resourceAssociations/$a"
    M=$(az resource show --ids "$ID" --api-version "$API" --query 'properties.accessMode' -o tsv 2>/dev/null || echo "")
    P=$(az resource show --ids "$ID" --api-version "$API" --query 'properties.provisioningState' -o tsv 2>/dev/null || echo "")
    [[ "$M" != "$TARGET_MODE" || "$P" != "Succeeded" ]] && ALL_GOOD=0
  done
  [[ $ALL_GOOD -eq 1 ]] && { echo "✔ all associations are $TARGET_MODE/Succeeded"; exit 0; }
  sleep 5
done
echo "✗ timed out"; exit 2
