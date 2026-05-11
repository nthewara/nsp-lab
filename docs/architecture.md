# Architecture

## One picture

```mermaid
flowchart TB
  subgraph SUB["Subscription &lt;your-sub-id&gt;"]
    subgraph RG["RG rg-nsp-lab"]
      LAW[("Log Analytics law-nsp-lab")]
      UAMI[["uami-nsp-lab"]]
      FLOWST[("Storage stflownsplab raw flow logs")]
      subgraph VNET["VNet vnet-nsp-lab 10.50.0.0/16"]
        JUMP["Jump VM vm-nsp-jump Ubuntu B2s"]
      end
      subgraph NSP["nsp-lab-perimeter (NSP)"]
        PROFILE["profile-default Inbound subscriptions=[this sub]"]
        KV["Key Vault kv-nsp-x"]
        ST["Storage stnspx"]
        SQL["Azure SQL sql-nsp-x"]
        AOAI["AI Services aoai-nsp-x gpt-4o-mini"]
        FP["Foundry Project proj-nsp-x"]
        SRCH["AI Search srch-nsp-x"]
        COS["Cosmos DB cos-nsp-x"]
      end
    end
  end
  CLIENT(("Laptop / internet"))
  CLIENT -->|"publicNetworkAccess=Enabled NSP decides per accessMode"| NSP
  JUMP -->|"same sub - matches profile"| NSP
  VNET -->|"VNet flow logs + Traffic Analytics"| FLOWST
  FLOWST -->|"flow + Traffic Analytics"| LAW
  NSP -->|"NSP diagnostic categories"| LAW
  KV & ST & SQL & AOAI & SRCH & COS -->|"resource-native diags"| LAW
  FP --- AOAI
```

## Components

| Component | SKU / mode | In perimeter? | Why |
|---|---|---|---|
| Key Vault `kv-nsp-…` | Standard, RBAC, soft-delete on | ✅ | Holds zero secrets (intentionally) — proves NSP works over a KV with `publicNetworkAccess=Enabled` |
| Storage `stnsp…` | StorageV2, RA-LRS, key access disabled, MI only | ✅ | Backing store for Foundry uploads in demo 2 |
| Azure SQL `sql-nsp-…/db-nsp-lab` | Server + Basic DB, Entra-only auth | ✅ | Demo 1 writes here |
| AI Services `aoai-nsp-…` | Multi-service S0 (`Microsoft.CognitiveServices/accounts` kind=AIServices) + `gpt-4o-mini` deployment | ✅ | Foundry + AOAI inference |
| Foundry project `proj-nsp-…` | New simplified model: `Microsoft.CognitiveServices/accounts/projects` | ✅ via parent | Agent + file_search demo |
| AI Search `srch-nsp-…` | Basic, MI auth | ✅ | Vector store for file_search |
| Cosmos DB `cos-nsp-…` | Serverless, SQL API | ✅ | Stores agent state / threads |
| Log Analytics `law-nsp-lab` | PerGB2018, 30 day retention | ❌ | Sink for all NSP diag categories |
| UAMI `uami-nsp-lab` | UserAssigned | ❌ | Single identity attached to jump VM + Foundry connections; granted data-plane roles |
| Jump VM `vm-nsp-jump` | Ubuntu 22.04, B2s, public IP, NSG :22 from your IP | ❌ | "Inside the sub" demo client |
| NSP `nsp-lab-perimeter` | 1 default profile, 2 access rules | n/a | The thing under test |

## NSP layout

```text
nsp-lab-perimeter
└── profiles/
    └── default
        ├── accessRules/
        │   ├── allow-sub-inbound  (Inbound,  subscriptions=[sub])
        │   └── allow-sub-outbound (Outbound, subscriptions=[sub])
        └── resourceAssociations/
            ├── kv-assoc        accessMode=Learning
            ├── storage-assoc   accessMode=Learning
            ├── sql-assoc       accessMode=Learning
            ├── aoai-assoc      accessMode=Learning
            ├── search-assoc    accessMode=Learning
            └── cosmos-assoc    accessMode=Learning
```

`scripts/20-toggle-enforced.sh` flips every association to `Enforced`. `21-toggle-learning.sh` flips them back.

## Per-demo flow

### Demo 1 — SQL writes
```mermaid
sequenceDiagram
  participant Lap as Laptop
  participant Jump as Jump VM (UAMI)
  participant NSP as NSP
  participant SQL as Azure SQL
  participant LAW as Log Analytics

  Jump->>NSP: TDS connect, Entra token (UAMI)
  NSP->>NSP: source IP in subscription? yes
  NSP->>SQL: allowed
  SQL-->>Jump: INSERT 1 row
  NSP-->>LAW: NetworkSecurityPerimeterAccessRule (matched allow-sub-inbound)
  Lap->>NSP: TDS connect from internet
  NSP->>NSP: Learning - allow + log / Enforced - deny + log
  NSP-->>LAW: NetworkSecurityPerimeterPublicAccessAttempt
```

### Demo 2 — Foundry knowledge agent
```mermaid
sequenceDiagram
  participant Dev as Dev / chat.py
  participant Proj as Foundry Project
  participant AOAI as gpt-4o-mini
  participant Srch as AI Search
  participant Strg as Storage (project files)

  Dev->>Proj: upload q3-report.md
  Proj->>Strg: PUT blob (transits NSP outbound: this-sub allowed)
  Dev->>Proj: create agent (file_search tool)
  Dev->>Proj: thread.run("what was Q3 revenue?")
  Proj->>AOAI: chat completions
  AOAI->>Srch: vector lookup
  Srch->>Strg: read chunks
  AOAI-->>Dev: "Q3 revenue was $4.2M…"
```

### Demo 3 — Lockdown
```mermaid
sequenceDiagram
  participant Lap as Laptop
  participant Jump as Jump VM
  participant NSP as NSP (Enforced)
  participant KV as KV/Storage/AOAI

  Lap->>KV: GET (public IP)
  NSP->>NSP: Enforced + no rule matches
  NSP-->>Lap: 403 NetworkSecurityPerimeterDenied
  NSP-->>LAW: PublicAccessAttempt: Result=Denied

  Jump->>KV: same call, same MI
  NSP->>NSP: subscriptions rule matches
  NSP-->>KV: allowed
  KV-->>Jump: 200 OK
```

## Naming

`<resource-prefix>-nsp-<4-char-rand>` keeps things globally unique. Override with `var.name_prefix` in tfvars.
