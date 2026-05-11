#!/usr/bin/env bash
# Run ON THE JUMP VM. Uses the attached UAMI for Entra auth.
set -eu
set -o pipefail || true

SQL_FQDN="${SQL_FQDN:?set SQL_FQDN to the SQL server FQDN}"
DB="${DB:-db-nsp-lab}"
UAMI_CLIENT_ID="${UAMI_CLIENT_ID:?set UAMI_CLIENT_ID}"

# Token via IMDS — sqlcmd supports access tokens via -P with --authentication-method=ActiveDirectoryAccessToken
TOKEN=$(curl -s -H "Metadata: true" \
  "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fdatabase.windows.net%2F&client_id=$UAMI_CLIENT_ID" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')

[[ -z "$TOKEN" ]] && { echo "failed to get IMDS token"; exit 1; }

MSG="hello from jump $(hostname) at $(date -u +%FT%TZ)"
sqlcmd -S "$SQL_FQDN" -d "$DB" --authentication-method=ActiveDirectoryAccessToken -P "$TOKEN" \
  -Q "INSERT INTO dbo.events (source, message) VALUES (N'jump-vm', N'$MSG'); SELECT TOP 5 id, source, message, created_at FROM dbo.events ORDER BY id DESC;" -b

echo "✔ insert from jump VM succeeded"
