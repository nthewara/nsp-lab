# Demo 2 — Foundry knowledge agent

> Proves: AOAI ↔ AI Search ↔ Cosmos ↔ Storage all transit the perimeter and still answer correctly. The agent uses **file_search** over a synthetic Q3 financial report.

## Steps

```bash
# 1. Set up Python env (one-time)
python3 -m venv .venv && source .venv/bin/activate
pip install azure-identity azure-ai-projects openai

# 2. Upload the sample report to the project's default file storage
python3 upload-files.py

# 3. Create an agent with the file_search tool
python3 create-agent.py        # prints AGENT_ID

# 4. Chat
AGENT_ID=<from previous> python3 chat.py "what was Q3 revenue?"
```

You should see an answer like *"Q3 revenue was $4.2M, up 18% YoY"* with citations from `q3-report.md`.

## What the lab is showing you under the hood

```text
chat.py (your laptop)
  ↓  PROJECT_ENDPOINT (Foundry data plane, AAD token from azure-identity)
Foundry Project
  ↓  AOAI inference   ──→ gpt-4o-mini deployment           (NSP-protected)
  ↓  file_search call ──→ AI Search index                  (NSP-protected)
  ↓  vector fetch     ──→ Storage blob in project files    (NSP-protected)
```

Every hop is inside the same subscription, so the default profile's `subscriptions=[thisSub]` allow rule matches. In Enforced mode, this still works. **If you remove the rule, file_search silently returns no chunks** — see `docs/gotchas.md` for that bear trap.

## KQL

After a chat, run [`kql/foundry-nsp-logs.kql`](kql/foundry-nsp-logs.kql) in LAW. You'll see traffic on the AOAI, Search, and Storage `ResourceId`s.
