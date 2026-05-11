#!/usr/bin/env bash
# Destroy in reverse order, then optionally nuke the state RG.
set -eu
set -o pipefail || true

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TFVARS="${TFVARS:-$HOME/workspace/tfvars/nsp-lab.tfvars}"
BACKEND="${BACKEND:-$HOME/workspace/tfvars/nsp-lab-backend.hcl}"
AUTO="${1:-}"

STAGES=( 55-flow-logs 50-diagnostics 40-associations 30-foundry 20-resources 10-perimeter )
for s in "${STAGES[@]}"; do
  echo "→ destroying $s"
  cd "$ROOT/infra/terraform/$s"
  terraform init -reconfigure -backend-config="$BACKEND"
  if [[ "$AUTO" == "--auto-approve" ]]; then
    terraform destroy -auto-approve -var-file="$TFVARS"
  else
    terraform destroy -var-file="$TFVARS"
  fi
done

echo
echo "Lab resources destroyed."
echo "To remove the isolated state storage too, run:"
echo "  az group delete -n tfstate-nsp-lab -y --no-wait"
echo
echo "Remember to update the lab tracker:"
echo "  python3 ~/.openclaw/skills/azure-labs/scripts/labs.py update --name nsp-lab --status destroyed"
