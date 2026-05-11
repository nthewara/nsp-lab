# Blockers & quirks encountered during the build

## Resolved

### sqlcmd v18 (legacy) vs go-sqlcmd v1.8.2
The Ubuntu 24.04 `mssql-tools18` package installs the legacy `sqlcmd` v18 which does **not** support `--authentication-method` or access-token auth. We replaced it with `go-sqlcmd` v1.8.2 on the jump VM and use `--authentication-method=ActiveDirectoryManagedIdentity -U <UAMI_CLIENT_ID>`. The Mac uses the brew-installed `sqlcmd` (also go-sqlcmd) with `--authentication-method=ActiveDirectoryAzCli` for the laptop seed.

### Tenant policy disables `allowSharedKeyAccess` on new storage accounts
A tenant-level default policy auto-flips new storage accounts to `allowSharedKeyAccess=false` within ~seconds of creation. The `azurerm_storage_account` resource's post-create data-plane wait then fails with `KeyBasedAuthenticationNotPermitted` even though the resource is created fine. **Workaround:** create the flow-logs storage account with `azapi_resource` (no post-create probe). Network Watcher writes via ARM-managed identity so it works without shared keys.

### Diagnostic categories: resource-rule categories are off by default in azurerm
We were enabling only the "perimeter rule" deny/allow categories. The actually interesting events (`NspPublicInboundResourceRulesDenied` etc.) only flow once you explicitly add them. Fixed in `50-diagnostics/main.tf`.

### Mermaid render on github.com
Node labels containing `<br/>`, `(`, `)`, or `:` need to be wrapped in double quotes. Done in `README.md`.

### Foundry project connections (`Microsoft.CognitiveServices/accounts/connections`) 4xx during apply
The new simplified Foundry-project API surface keeps shifting between account-level and project-level. We omit the explicit connections in this lab; the `file_search` agent can use the AOAI MSI's default resource lookups. Notes left inline in `30-foundry/main.tf` for re-adding them when GA.

## Workarounds in place

### Seeding the SQL DB from the laptop
Requires a temporary SQL server firewall rule for the laptop's public IP (`az sql server firewall-rule create … --name seed-laptop …`). The script `seed-from-here.sh` documents this; remove the rule after seeding (`az sql server firewall-rule delete -n seed-laptop`). The NSP doesn't block this because the firewall sits in front of NSP in the access decision chain; for the demo, run the seed once before flipping to Enforced.

### `mapfile` on macOS bash
`mapfile -t` is bash 4+; macOS ships bash 3.2. The `scripts/20-toggle-enforced.sh` script was rewritten with a `while read` loop. Run with `/bin/bash` rather than `bash` to dodge any `zsh` shims.

## Skipped

### Portal screenshots
The OpenClaw browser couldn't attach to the user's Chrome profile during this run. Evidence files in `docs/evidence/` substitute: NSP topology dump, LAW NSP entries showing the deny+allow side-by-side from two source IPs, flow-log config, and a full denied-event JSON.

### Demo 2 (Foundry knowledge agent) end-to-end
Foundry project deployed and connections role-assigned, but the data-plane `file_search` agent flow needs further work — the new Foundry project API surface for uploading files + creating an agent is in flux. The infrastructure is in place; the demo script (`demos/demo-2-foundry-knowledge/`) is left as-is for a follow-up.
