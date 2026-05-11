#!/usr/bin/env bash
# Run ON THE JUMP VM. Uses the attached UAMI for Entra auth via go-sqlcmd's
# ActiveDirectoryManagedIdentity provider.
set -eu
set -o pipefail || true

SQL_FQDN="${SQL_FQDN:?set SQL_FQDN to the SQL server FQDN}"
DB="${DB:-db-nsp-lab}"
UAMI_CLIENT_ID="${UAMI_CLIENT_ID:?set UAMI_CLIENT_ID}"

MSG="hello from jump $(hostname) at $(date -u +%FT%TZ)"
sqlcmd -S "$SQL_FQDN" -d "$DB" --authentication-method=ActiveDirectoryManagedIdentity -U "$UAMI_CLIENT_ID" \
  -Q "INSERT INTO dbo.events (source, message) VALUES (N'jump-vm', N'$MSG'); SELECT TOP 5 id, source, message, created_at FROM dbo.events ORDER BY id DESC;" -b

echo "✔ insert from jump VM succeeded"
