# nsp-lab — Azure Network Security Perimeter, end-to-end

> A reproducible lab that puts **Key Vault, Storage, Azure SQL, AI Services + Foundry, AI Search, and Cosmos DB** behind a single **Network Security Perimeter (NSP)** with full **NSP diagnostic logging** to **Log Analytics**, then proves it works across **three progressive demos**.

```mermaid
flowchart LR
  subgraph PERIMETER["nsp-lab-perimeter (NSP) — default profile"]
    KV[Key Vault]
    ST[Storage]
    SQL[Azure SQL]
    AOAI[AI Services + Foundry project]
    SRCH[AI Search]
    COS[Cosmos DB]
  end
  JUMP[Jump VM<br/>(UAMI)] -->|inside subscription:<br/>allowed by default profile| PERIMETER
  NET((Public internet)) -.->|Learning: allowed + logged<br/>Enforced: 403 + logged| PERIMETER
  PERIMETER -- "NetworkSecurityPerimeterAccessRule<br/>NetworkSecurityPerimeterPublicAccessAttempt" --> LAW[(Log Analytics<br/>law-nsp-lab)]
```

## What this proves

1. **Demo 1 — SQL writes through the perimeter.** Jump-VM uses its UAMI (Entra-only auth) to write rows to Azure SQL; KQL shows the access. From the public internet, same call is logged in Learning mode and **blocked** in Enforced mode.
2. **Demo 2 — A Foundry "knowledge" agent.** Upload a synthetic Q3 report → create an AI Foundry agent with `file_search` → ask "what was Q3 revenue?". Behind the scenes AOAI ↔ AI Search ↔ Storage all transit the perimeter while still answering correctly.
3. **Demo 3 — Public lockdown.** Flip to Enforced. From your laptop, `curl` against AOAI / Storage / Key Vault returns **403**. From the jump VM, the exact same calls still work. LAW shows the denies.

## Headline policy

> **Every resource keeps `publicNetworkAccess = Enabled`.** NSP layers on top. The point is to show that NSP can secure resources that don't use Private Link / VNet integration — that's the whole pitch.

## Quick start (5 commands)

```bash
# 0. Pre-reqs: az login, terraform >=1.6, gh, jq, sqlcmd (mssql-tools18), python3
git clone https://github.com/nthewara/nsp-lab && cd nsp-lab

# 1. Bootstrap a fresh, isolated tfstate storage account
./scripts/00-bootstrap-state.sh

# 2. Deploy everything (foundation → resources → foundry → associations → diagnostics)
./scripts/10-deploy.sh

# 3. Status snapshot (NSP mode, association modes)
./scripts/30-status.sh

# 4. Run the demos
( cd demos/demo-1-sql-writes && bash insert-from-allowed.sh )
( cd demos/demo-2-foundry-knowledge && python3 chat.py )
( cd demos/demo-3-public-lockdown && bash prove-public-blocked.sh )

# 5. Flip enforcement on/off
./scripts/20-toggle-enforced.sh   # tighten
./scripts/21-toggle-learning.sh   # loosen
```

## Cost

≈ **$11 / day** at idle (S0 SQL ≈ $0.50, AI Search Basic ≈ $2.50, Jump VM B2s ≈ $1.20, AOAI gpt-4o-mini pay-as-you-go, Cosmos serverless near-zero, KV/Storage cents). NSP itself is **free**.

## Cleanup

```bash
./scripts/99-teardown.sh
```

Then run the same `labs.py` `update --status destroyed` line emitted by the teardown.

## Layout

```
infra/terraform/00-foundation   # isolated tfstate storage (one-off)
infra/terraform/10-perimeter    # RG + LAW + UAMI + NSP + default profile + jump VM + VNet
infra/terraform/20-resources    # KV / Storage / SQL / AI Services / AI Search / Cosmos
infra/terraform/30-foundry      # AI Foundry project + connections + file upload + gpt-4o-mini
infra/terraform/40-associations # Bind all six resources to the perimeter
infra/terraform/50-diagnostics  # Diagnostic settings → LAW (NSP + resource categories)
demos/                          # The three demos
kql/                            # Reusable LAW queries + a workbook
docs/                           # Concepts, gotchas, demo script, screenshots
scripts/                        # Deploy / toggle / status / teardown helpers
```

## Auth note (NO KEYS)

- All resources are **MI-only** via a shared UAMI `uami-nsp-lab`
- Storage account keys, AOAI API keys, SQL SQL-auth, AI Search admin keys — **none used**
- SQL uses **Entra-only authentication**; the agent service principal is the Entra admin, and a contained user is created for the UAMI

## Isolated state

State lives in a brand-new RG `tfstate-nsp-lab` with a brand-new account `tfstatensplab<rand>` — **not** the user's existing tfstate. Easy to nuke independently.

## Docs

- [`docs/architecture.md`](docs/architecture.md) — diagrams + per-demo flow
- [`docs/nsp-concepts.md`](docs/nsp-concepts.md) — what NSP is, primer + Microsoft Learn links
- [`docs/observability.md`](docs/observability.md) — log schema, sample KQL
- [`docs/gotchas.md`](docs/gotchas.md) — pitfalls (file_search, MI, public-access, association propagation)
- [`docs/demo-script.md`](docs/demo-script.md) — 15-20 min presenter walkthrough

## License

MIT — see [LICENSE](LICENSE).
