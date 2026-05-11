# Observability

The whole point of NSP for an SRE is the **uniform log schema** across every resource type. This file is the cheat sheet.

## Where the logs live

| Log destination | Table | Categories |
|---|---|---|
| Log Analytics `law-nsp-lab` | `AzureDiagnostics` | `NetworkSecurityPerimeterAccessRule`, `NetworkSecurityPerimeterPublicAccessAttempt` (every resource), plus resource-native (e.g. `KeyVaultAuditEvent`, `SQLSecurityAuditEvents`) |

> Both NSP categories are enabled on **all** in-perimeter resources by `infra/terraform/50-diagnostics`. They're also enabled on the NSP itself.

## Schema you actually use

### NetworkSecurityPerimeterAccessRule

```
TimeGenerated        : datetime
Category             : "NetworkSecurityPerimeterAccessRule"
ResourceId           : /subscriptions/.../<resource>
profileName_s        : "default"
matchedRule_s        : "allow-sub-inbound"  (or "_NoRuleMatched")
direction_s          : "Inbound" | "Outbound"
accessRule_s         : "<json blob of the matched rule>"
sourceIPAddress_s    : "203.0.113.4"
sourcePort_s         : "54321"
destinationIPAddress_s
serverPort_s
action_s             : "Allowed" | "Denied"
accessMode_s         : "Learning" | "Enforced" | "Audit"
```

### NetworkSecurityPerimeterPublicAccessAttempt

```
TimeGenerated
Category             : "NetworkSecurityPerimeterPublicAccessAttempt"
ResourceId           : /subscriptions/.../<resource>
serviceResourceId_s  : same as ResourceId for most
sourceIPAddress_s    : "203.0.113.4"
result_s             : "Allowed" | "Denied"
accessMode_s         : "Learning" | "Enforced" | "Audit"
profileName_s
direction_s
operationName_s
matchedRule_s
```

Field suffixes (`_s`, `_d`, `_b`) are LAW's auto-typing; resource-native categories can rename slightly across providers — always `extend` and `project` rather than relying on raw column order.

## Starter queries (`kql/`)

All copy-pastable into the LAW Logs blade.

- `all-nsp-events.kql` — last hour, both categories, both directions
- `access-rule-hits.kql` — top matched rules grouped by resource
- `inbound-denied.kql` — denies caused by no inbound rule match (the "you need to add an exception" view)
- `outbound-denied.kql` — same for outbound
- `learning-mode-summary.kql` — sources & destinations that *would* be denied if you went Enforced — the **flip-readiness** view
- `workbook.json` — importable LAW workbook with five tiles

## Plan-before-flip recipe

```kusto
AzureDiagnostics
| where TimeGenerated > ago(24h)
| where Category == "NetworkSecurityPerimeterPublicAccessAttempt"
| where accessMode_s == "Learning"
| where result_s == "Allowed"
| where matchedRule_s == "_NoRuleMatched"   // these would deny in Enforced
| summarize attempts = count(),
            sources  = make_set(sourceIPAddress_s, 10),
            sample_ops = make_set(operationName_s, 5)
  by tostring(split(ResourceId, "/")[-1]), direction_s
| order by attempts desc
```

Anything in that table needs a new access rule before you flip the association to Enforced.

## Per-resource native log categories (also enabled)

| Resource | Category |
|---|---|
| Key Vault | `AuditEvent` |
| Storage  | `StorageRead`, `StorageWrite`, `StorageDelete` (blob, table, queue) |
| Azure SQL | `SQLSecurityAuditEvents` (server-level via auditing → LAW) — *optional*, off by default to save log cost |
| AI Services | `Audit`, `RequestResponse` |
| AI Search | `OperationLogs` |
| Cosmos DB | `DataPlaneRequests` |

These coexist with the NSP categories and let you cross-reference a denial with what the resource itself *would have* logged.
