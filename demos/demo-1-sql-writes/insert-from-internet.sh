#!/usr/bin/env bash
# Run from your LAPTOP, signed in as the agent SP. Uses your interactive token.
# In Learning mode: succeeds (and is logged). In Enforced: fails with NSP denial.
set -eu
set -o pipefail || true

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BACKEND="${BACKEND:-$HOME/workspace/tfvars/nsp-lab-backend.hcl}"
cd "$ROOT/infra/terraform/20-resources"
terraform init -reconfigure -backend-config="$BACKEND" >/dev/null
SQL_FQDN=$(terraform output -raw sql_server_fqdn)
DB=$(terraform output -raw sql_db_name)

MSG="hello from internet $(hostname) at $(date -u +%FT%TZ)"
echo "→ inserting via $SQL_FQDN ($DB) from $(curl -s ifconfig.me 2>/dev/null || echo '<local>')"
set +e
sqlcmd -S "$SQL_FQDN" -d "$DB" --authentication-method=ActiveDirectoryAzCli \
  -Q "INSERT INTO dbo.events (source, message) VALUES (N'laptop', N'$MSG'); SELECT TOP 3 id, source, message FROM dbo.events ORDER BY id DESC;" -b
RC=$?
set -e
if [[ $RC -eq 0 ]]; then
  echo "✔ insert from internet succeeded (Learning mode → check LAW for 'allowed but would deny' signal)"
else
  echo "✗ insert from internet FAILED (rc=$RC) — expected if perimeter is Enforced. Check LAW for 'Denied' row."
fi
