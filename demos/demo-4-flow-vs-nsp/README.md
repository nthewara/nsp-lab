# Demo 4 — VNet flow logs vs NSP logs (two lenses, one LAW)

> Proves: the same network event shows up in **two complementary logs** going to the same workspace. NSP tells you *whether the Azure resource access was allowed*; flow logs tell you *what packets actually traversed the VNet*.

## What gets enabled

- `infra/terraform/55-flow-logs` provisions:
  - `stflownsplab…` — a Standard_LRS storage account holding the raw flow logs (10-day retention)
  - `fl-nsp-lab-vnet` — VNet flow log v2 bound to `vnet-nsp-lab`
  - Traffic Analytics → `law-nsp-lab` (same workspace as NSP diagnostics), 10-minute aggregation
- Network Watcher (`NetworkWatcher_<region>`) is auto-created by Azure; we reference it via `data` lookup.

## Steps

1. Run **Demo 1** end-to-end first (or any traffic from the jump VM to Azure SQL):
   ```bash
   ( cd demos/demo-1-sql-writes && bash insert-from-internet.sh )
   # …and on the jump VM:
   bash demos/demo-3-public-lockdown/prove-internal-allowed.sh
   ```

2. **Wait ~10 minutes.** Traffic Analytics aggregates on a 10-min interval; rows in `AzureNetworkAnalytics_CL` lag behind real traffic. NSP rows in `AzureDiagnostics` show up in ~1–2 minutes.

3. Run the side-by-side KQL:
   ```kusto
   // paste from kql/vnet-flow-vs-nsp.kql
   ```

## What you should see

For a SQL connect from the **jump VM** in Learning mode:
- **NSP row** → `nspMode=Learning`, `nspRule=allow-sub-inbound`, `nspResult=Allowed`, `resource=sql-nsp-lab-<sfx>`.
- **Flow row** → `SrcIP=<jump private IP>`, `DestPort=1433`, `L4Protocol=T`, `AllowedInFlows>0`, `DeniedInFlows=0`, `FlowDirection=O` (outbound).

For a SQL connect from the **laptop** in Enforced mode:
- **NSP row** → `nspMode=Enforced`, `nspRule=_NoRuleMatched`, `nspResult=Denied`, `resource=sql-nsp-lab-<sfx>`.
- **Flow row** → the *outbound TDS connect* from your home IP still appears on the VNet side **only if** the laptop attempts via the VPN/jump path; otherwise this side will be empty. The point: NSP can deny at the Azure control plane *before* the VNet sees anything, which is exactly the value-add.

## Schema note (mid-2026)

- Legacy table `AzureNetworkAnalytics_CL` is still the broadly available one.
- New typed table `NTANetAnalytics` is being rolled out. If your workspace has it, swap `SrcIP_s → SrcIp`, `DestPort_d → DestPort`, etc. See [docs/observability.md](../../docs/observability.md#vnet-flow-logs-vs-nsp-logs--two-lenses-one-law).

## Why this matters in a real estate

- **NSP without flow logs**: you know who got denied at the resource, but not how that flowed across your VNet/peerings.
- **Flow logs without NSP**: you see packets but you don't know whether AOAI denied the call at the resource boundary or your client misbehaved.
- **Both, same LAW**: one query can correlate the two. That's the lab's pitch.
