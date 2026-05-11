# Demo script — 15-20 minute walkthrough

Suggested running order for a live demo. Total ≈ 18 min if everything's already deployed.

---

## 0. Setup before the meeting (1 min, off camera)

```bash
./scripts/00-bootstrap-state.sh    # only ever once
./scripts/10-deploy.sh --auto-approve
( cd demos/demo-1-sql-writes && bash seed-from-here.sh )
( cd demos/demo-2-foundry-knowledge && python3 upload-files.py && python3 create-agent.py | tee /tmp/agent.txt )
```

Confirm `./scripts/30-status.sh` shows all six associations as `Learning / Succeeded`.

---

## 1. The big picture (2 min)

- Open the portal → RG `rg-nsp-lab-XXXX`.
- Walk through the 6 in-perimeter resources. **Highlight: every single one shows `publicNetworkAccess = Enabled`.**
- Open NSP `nsp-lab-perimeter` → **Resources** tab → six rows, all in `Learning`.
- Talking point: *"Today, none of these have any firewall config. They're wide open by the resource's own settings. The headline of this lab is that NSP lets us layer perimeter control on top of that, without touching any of these resources."*

---

## 2. Demo 1 — SQL writes (3 min)

- Terminal A (laptop):
  ```bash
  cd demos/demo-1-sql-writes
  bash insert-from-internet.sh
  ```
  ✅ Succeeds because we're in Learning. Show the SELECT output.

- Terminal B (jump VM via SSH wrapper):
  ```bash
  bash demos/demo-3-public-lockdown/prove-internal-allowed.sh   # also includes a SQL hit if extended; alternatively run insert-from-allowed.sh on the VM
  ```
  ✅ Succeeds. Inside-sub.

- LAW: paste `demos/demo-1-sql-writes/kql/sql-nsp-logs.kql`. Show **both events**:
  - Jump VM call → `accessMode = Learning`, matched `allow-sub-inbound` rule.
  - Laptop call → `accessMode = Learning`, `matchedRule = _NoRuleMatched`, result `Allowed`. *"This is the flip-readiness signal — when we enforce, this exact row becomes Denied."*

---

## 3. Demo 2 — Foundry knowledge agent (4 min)

- Laptop:
  ```bash
  cd demos/demo-2-foundry-knowledge
  AGENT_ID=$(grep AGENT_ID= /tmp/agent.txt | cut -d= -f2)
  python3 chat.py "What was Q3 revenue and which region led it?"
  ```
- Agent answers `$4.2M, APAC led at $1.85M (44%)`.
- Talking points (this is where you sell):
  - "We didn't change anything in the agent code — it talks to AOAI which talks to AI Search which reads from Storage. All three are inside the perimeter."
  - "The data plane traffic is all `subscriptions=[thisSub]` from Azure's perspective, so the default profile lets it through."
- LAW: paste `demos/demo-2-foundry-knowledge/kql/foundry-nsp-logs.kql` — show rows hitting AOAI, Search, **and** Storage.

---

## 4. Demo 3 — Lockdown (5 min)

- Show current state: `./scripts/30-status.sh` (all Learning).
- Run the laptop calls in Learning to set a baseline:
  ```bash
  bash demos/demo-3-public-lockdown/prove-public-blocked.sh
  ```
  ✅ All three return 200.

- **Flip the perimeter:**
  ```bash
  ./scripts/20-toggle-enforced.sh
  ```
  Wait for the "✔ all associations are Enforced/Succeeded" line (≈ 60–90s — narrate the *eventual consistency* point here).

- Replay laptop calls:
  ```bash
  bash demos/demo-3-public-lockdown/prove-public-blocked.sh
  ```
  🛑 All three return 403 with `x-ms-error-code: NetworkSecurityPerimeterDenied`. Read the headers out loud.

- Replay from the jump VM:
  ```bash
  bash demos/demo-3-public-lockdown/prove-internal-allowed.sh
  ```
  ✅ All three still succeed. **This is the punchline.**

- LAW: paste `demos/demo-3-public-lockdown/kql/denied-requests.kql`. Show one denied row per call, with your laptop's source IP and the resource that denied.

---

## 5. Re-cap & cleanup (2 min)

- Pull up `kql/learning-mode-summary.kql` — *"this is how you plan a flip in real life: get an empty result here before going Enforced."*
- Flip back to Learning so the lab stays demoable:
  ```bash
  ./scripts/21-toggle-learning.sh
  ```
- Optional teardown:
  ```bash
  ./scripts/99-teardown.sh
  ```

## Presenter cheat sheet

| Question | Answer |
|---|---|
| "What if I don't have NSP capacity in my sub?" | NSP is GA and free; you may need to register `Microsoft.Network` features — see `docs/blockers.md` if one happens. |
| "Does this replace Private Endpoint?" | No. PE gives you a private IP. NSP gives you a perimeter at the resource level. Use both for defense-in-depth. |
| "Can I do per-app micro-perimeters?" | Yes — multiple profiles on one NSP, different rules per profile, different associations on each. |
| "What about cross-tenant?" | NSP has *Links* between perimeters in the same or different tenants (`networkSecurityPerimeters/links`). Out of scope for this lab. |
| "Why is Learning still 'allowed' for blocked traffic?" | Learning means **the resource's own controls apply**. NSP only logs. That's why `publicNetworkAccess=Enabled` matters here. |
