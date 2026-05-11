# Gotchas

Things that bit us so you don't have to. Roughly in the order they will bite a presenter.

## 1. NSP is not in `azurerm` (yet) — use `azapi`

As of `hashicorp/azurerm` v4.x, there is **no** native resource for `Microsoft.Network/networkSecurityPerimeters`. Two options:

- `azapi_resource` (this lab's choice). Stable, GA API `2024-07-01`.
- AzureRM provider preview branches.

This lab pins `azapi >= 2.0` and uses GA `2024-07-01`. If your sub gets the preview features (Audit mode tweaks etc.), pin to `2024-10-01` instead.

## 2. Learning mode is **not** "warn-only" for *resource-native* policies

Putting an association in Learning **does not** disable the resource's own firewall, ACLs, or RBAC. If your Storage account has `defaultAction=Deny` and no firewall rules, Learning mode will not magically let you in — NSP only adds *its own* layer. Always start with `publicNetworkAccess = Enabled` and resource firewall = open while building the lab. The whole point of NSP here is that you don't *need* to lock down the resource's own firewall.

## 3. The Foundry agent's `file_search` tool requires the perimeter to allow the agent's call path

In Learning mode this is invisible. In Enforced mode, if your `Inbound` rule on the AI Services account doesn't cover the source (here: the subscription itself, because Foundry calls AOAI via the management plane), `file_search` returns an empty knowledge set — and the agent will silently say "I don't know". Both rules in the default profile have `subscriptions = [thisSub]` to make this work.

## 4. Use **managed identity**, not API keys

- AOAI: do **not** use `api-key`. Use the UAMI's bearer token; AOAI accepts Entra tokens out of the box. The `chat.py` demo shows the correct flow.
- Storage: account keys are **disabled** in this lab — `shared_access_key_enabled = false`.
- AI Search: admin & query keys are not used; UAMI holds `Search Service Contributor` + `Search Index Data Contributor`.
- SQL: server has `azuread_authentication_only = true`. Local-auth SQL logins **will not work**.
- Key Vault: `enable_rbac_authorization = true`. Access policies are not configured.

## 5. SQL Entra-only needs **two** pieces

1. Set the agent service principal (or an Entra group) as the **server admin** (`administrator_login` block).
2. After deploy, run `seed.sql` as that admin (using `sqlcmd -G -U <SP> -P <token>`) which creates the UAMI as a **contained user** and grants `db_datareader, db_datawriter`. Until you run the seed, the UAMI can authenticate to the server but not the DB.

The `demos/demo-1-sql-writes/seed.sql` is idempotent.

## 6. NSP association is async; toggle scripts wait

Switching an association from Learning → Enforced is *eventually consistent* — it can take 30–90 seconds before traffic actually starts being denied. `scripts/20-toggle-enforced.sh` polls until every association reports `accessMode = Enforced` *and* `provisioningState = Succeeded` before printing OK.

## 7. Resource type names don't match between Azure docs and `azapi`

- Azure docs say "Microsoft.Network/networkSecurityPerimeters/profiles/accessRules" — that's `azapi` `type = "Microsoft.Network/networkSecurityPerimeters/profiles/accessRules@2024-07-01"`. **3 levels** of parenting.
- Resource associations are at the **perimeter** level, not the profile: `…/networkSecurityPerimeters/resourceAssociations@2024-07-01`. They reference the profile by `properties.profile.id`. Easy to get wrong.

## 8. Cosmos DB needs **role assignment**, not just RBAC

For data-plane access, you must create a `Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments` for the UAMI. Adding `Cosmos DB Built-in Data Contributor` at the *control plane* (regular Azure RBAC) is **not** enough — that's a common mistake. The TF module includes both.

## 9. `gpt-4o-mini` capacity & region

- Region `australiaeast` has `gpt-4o-mini` capacity at time of writing; if your sub doesn't, change `var.aoai_model_location` to `eastus` and re-deploy. The Foundry project must be in the same account, so changing the AOAI region changes both.
- Default capacity in this lab: `30` TPM units. If quota denies, bump down to `10`.

## 10. Foundry project: use the **new** model

The lab uses `Microsoft.CognitiveServices/accounts/projects` (the simplified Foundry project that's a child of an AI Services account) — **not** the older `Microsoft.MachineLearningServices/workspaces` "hub + project" pair. Less code, fewer moving parts. Side-effect: connections live on the parent account, not the project.

## 11. Diagnostic settings can attach to NSP itself

You can (and should) put a diagnostic setting on `Microsoft.Network/networkSecurityPerimeters/<name>` directly to get the *aggregate* NSP signal — but you also need them on each *associated* resource to get per-resource context. The lab does both.

## 12. Don't reuse RG names after a destroy

Azure keeps the RG in a soft-delete-ish state for a few minutes; re-creating the same name immediately can 409. `99-teardown.sh` runs `--no-wait`; the deploy scripts use a randomised RG name by default.

## 13. The jump VM public IP is yours; lock it down

`vm-nsp-jump` has a public IP + NSG :22 allowing `var.allowed_ssh_cidr`. **Default is `0.0.0.0/0` so the lab Just Works** but you should set this to your actual IP / `curl ifconfig.me/32` in a real environment.
