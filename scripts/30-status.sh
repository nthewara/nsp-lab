#!/usr/bin/env bash
# Status snapshot: RG / NSP / profile / access rules / associations.
set -eu
set -o pipefail || true
SUB="${SUB:-$(az account show --query id -o tsv)}"
RG="$(az group list --query "[?starts_with(name,'rg-nsp-lab-')].name | [0]" -o tsv --subscription "$SUB")"
[[ -z "$RG" ]] && { echo "no nsp-lab RG found"; exit 1; }
NSP="$(az network perimeter list -g "$RG" --query '[0].name' -o tsv --subscription "$SUB")"

echo "Subscription : $SUB"
echo "RG           : $RG"
echo "NSP          : $NSP"
echo
echo "Profiles:"
az network perimeter profile list --perimeter-name "$NSP" -g "$RG" --subscription "$SUB" --query '[].{name:name}' -o table
echo
echo "Access rules (default profile):"
az network perimeter profile access-rule list --perimeter-name "$NSP" -g "$RG" --profile-name default --subscription "$SUB" \
  --query '[].{name:name, direction:properties.direction, subs:properties.subscriptions[].id, cidrs:properties.addressPrefixes, fqdns:properties.fullyQualifiedDomainNames}' -o table
echo
echo "Associations:"
az network perimeter association list --perimeter-name "$NSP" -g "$RG" --subscription "$SUB" \
  --query '[].{name:name, accessMode:properties.accessMode, state:properties.provisioningState, target:properties.privateLinkResource.id}' -o table
echo
JUMP=$(az vm list -g "$RG" --subscription "$SUB" --query "[?contains(name,'jump')].name | [0]" -o tsv)
[[ -n "$JUMP" ]] && {
  IP=$(az vm show -d -g "$RG" -n "$JUMP" --subscription "$SUB" --query publicIps -o tsv)
  echo "Jump VM      : $JUMP @ $IP   (ssh -i ~/.ssh/nsp_lab_ed25519 labadmin@$IP)"
}
LAW=$(az monitor log-analytics workspace list -g "$RG" --subscription "$SUB" --query '[0].name' -o tsv)
echo "LAW          : $LAW"
