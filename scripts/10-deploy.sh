#!/usr/bin/env bash
# Deploy all TF stages in order. Pass an extra `--auto-approve` to skip prompts.
set -eu
set -o pipefail || true

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TFVARS="${TFVARS:-$HOME/workspace/tfvars/nsp-lab.tfvars}"
BACKEND="${BACKEND:-$HOME/workspace/tfvars/nsp-lab-backend.hcl}"
AUTO="${1:-}"

[[ ! -f "$TFVARS"  ]] && { echo "missing $TFVARS"; exit 1; }
[[ ! -f "$BACKEND" ]] && { echo "missing $BACKEND — run 00-bootstrap-state.sh first"; exit 1; }

STAGES=( 10-perimeter 20-resources 30-foundry 40-associations 50-diagnostics )

for s in "${STAGES[@]}"; do
  echo
  echo "════════════════════════════════════════════════════════"
  echo "  Deploying $s"
  echo "════════════════════════════════════════════════════════"
  cd "$ROOT/infra/terraform/$s"
  terraform init -reconfigure -backend-config="$BACKEND"
  if [[ "$AUTO" == "--auto-approve" ]]; then
    terraform apply -auto-approve -var-file="$TFVARS"
  else
    terraform apply -var-file="$TFVARS"
  fi
done

echo
echo "✔ Deploy complete."
"$ROOT/scripts/30-status.sh" || true
