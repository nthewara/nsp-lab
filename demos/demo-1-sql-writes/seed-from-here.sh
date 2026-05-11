#!/usr/bin/env bash
# Run on your laptop (where az login is the agent SP / Entra admin).
# Seeds the events table and creates the UAMI as a contained DB user.
set -eu
set -o pipefail || true

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BACKEND="${BACKEND:-$HOME/workspace/tfvars/nsp-lab-backend.hcl}"
cd "$ROOT/infra/terraform/20-resources"
terraform init -reconfigure -backend-config="$BACKEND" >/dev/null

SQL_FQDN=$(terraform output -raw sql_server_fqdn)
DB=$(terraform output -raw sql_db_name)
cd "$ROOT/infra/terraform/10-perimeter"
terraform init -reconfigure -backend-config="$BACKEND" >/dev/null
UAMI=$(terraform output -raw uami_name)

echo "SQL  : $SQL_FQDN / $DB"
echo "UAMI : $UAMI"

SEED="$(cd "$ROOT/demos/demo-1-sql-writes" && pwd)/seed.sql"
TMP=$(mktemp)
sed "s/__UAMI_NAME__/$UAMI/g" "$SEED" > "$TMP"

# Use sqlcmd's Entra-Interactive or Entra-AzureCLI auth
command -v sqlcmd >/dev/null || { echo "install sqlcmd: brew tap microsoft/mssql-release && brew install mssql-tools18"; exit 1; }

echo "→ seeding…"
sqlcmd -S "$SQL_FQDN" -d "$DB" -G --authentication-method=ActiveDirectoryAzCli -i "$TMP" -b
rm -f "$TMP"
echo "✔ seed complete"
