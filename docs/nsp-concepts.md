# NSP concepts (the 5-minute primer)

## What is a Network Security Perimeter?

A **Network Security Perimeter (NSP)** is an Azure-wide logical boundary you can place around a set of supported PaaS resources. Resources inside an NSP can **only** communicate with:

1. Other resources in the **same** perimeter, **and**
2. Sources that match an **access rule** on the perimeter's profile.

Public network access to resources inside the perimeter is governed by NSP — **regardless** of whether the resource itself has `publicNetworkAccess = Enabled`. This is the headline feature: you don't have to refactor everything to Private Endpoint to get a sensible default-deny posture.

> Official docs: <https://learn.microsoft.com/azure/private-link/network-security-perimeter-concepts>

## The four objects you actually deal with

| Object | ARM type | What it does |
|---|---|---|
| Perimeter | `Microsoft.Network/networkSecurityPerimeters` | The container |
| Profile | `…/networkSecurityPerimeters/profiles` | A bundle of access rules; one perimeter can have many |
| Access rule | `…/profiles/accessRules` | Inbound / Outbound allow rules — match on IP CIDR, subscription, or FQDN (outbound only) |
| Resource association | `…/networkSecurityPerimeters/resourceAssociations` | Bind a specific PaaS resource to a profile, with `accessMode` Learning / Enforced / Audit |

> Spec: <https://learn.microsoft.com/azure/templates/microsoft.network/networksecurityperimeters>
> Resource associations: <https://learn.microsoft.com/azure/templates/microsoft.network/networksecurityperimeters/resourceassociations>

## Three association modes

| Mode | Behaviour |
|---|---|
| **Learning** | Default. Resource enforces its own public-access settings; NSP only **logs** what *would* happen if you went enforced. Use this to plan rules. |
| **Enforced** | NSP becomes authoritative. Anything not explicitly allowed by an access rule is **denied** and logged. |
| **Audit** | Like Learning but the resource still applies its own rules — primary difference is some signal granularity (provider-dependent). Lab does not use Audit. |

> Learn how to transition: <https://learn.microsoft.com/azure/private-link/network-security-perimeter-transition-to-enforced-mode>

## Supported resources (used in this lab)

| Resource | Status (Nov 2025) | Notes |
|---|---|---|
| Key Vault | GA | RBAC-mode only |
| Storage | GA | Blob + Table + Queue |
| Azure SQL DB | GA | Server-level association |
| AI Services / Azure OpenAI | GA | Multi-service or single |
| AI Search | GA | Basic SKU and above |
| Cosmos DB | GA | SQL API; data plane |
| AI Foundry project | Inherits parent AI Services association | New simplified model — see [`gotchas.md`](gotchas.md) |

> Current list: <https://learn.microsoft.com/azure/private-link/network-security-perimeter-concepts#onboarded-private-link-resources>

## Diagnostic categories

Enable both on every associated resource:

- `NetworkSecurityPerimeterAccessRule` — every rule evaluation (matched rule, direction, profile, action)
- `NetworkSecurityPerimeterPublicAccessAttempt` — every connection attempt from outside the perimeter, with Allowed / Denied result

LAW table is `AzureDiagnostics` — see [`observability.md`](observability.md) for shape and queries.

## Why this beats "VNet + Private Endpoint" for the demo

| | Private Endpoint | NSP |
|---|---|---|
| Cost | $0.01/hr × N PEs (~$3–8/day for 6 PEs) | Free |
| Refactor | App / clients must use private DNS | Zero — same public hostnames |
| Logging | Per-resource | Uniform NSP categories |
| Allows "trust by subscription" | No — IP-only | Yes — `subscriptions: [...]` |

NSP isn't a replacement for PE in every case, but for "lock down a sprawl of PaaS without rewiring", it's the right tool.

## Further reading

- Concepts: <https://learn.microsoft.com/azure/private-link/network-security-perimeter-concepts>
- Diagnostic logs: <https://learn.microsoft.com/azure/private-link/network-security-perimeter-diagnostic-logs>
- Transition to enforced: <https://learn.microsoft.com/azure/private-link/network-security-perimeter-transition-to-enforced-mode>
- ARM template reference: <https://learn.microsoft.com/azure/templates/microsoft.network/networksecurityperimeters>
- Onboarded resources: <https://learn.microsoft.com/azure/private-link/network-security-perimeter-concepts#onboarded-private-link-resources>
