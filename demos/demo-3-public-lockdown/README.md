# Demo 3 — Public lockdown

> Proves: with the perimeter in **Enforced** mode, public calls to AOAI / KV / Storage from the internet are **403 NetworkSecurityPerimeterDenied**, while the **same calls from the jump VM still work** — and both paths show up in LAW.

## Run order

```bash
# 1. Start in Learning mode (the default). Both calls succeed.
./scripts/30-status.sh                    # confirm accessMode=Learning everywhere
bash prove-internal-allowed.sh            # ✅ from jump (via SSH wrapper)
bash prove-public-blocked.sh              # ✅ also succeeds — Learning mode is permissive

# 2. Flip to Enforced
./scripts/20-toggle-enforced.sh

# 3. Replay
bash prove-internal-allowed.sh            # ✅ still works (inside-sub allow rule matches)
bash prove-public-blocked.sh              # 🛑 403 NetworkSecurityPerimeterDenied

# 4. See denies in LAW
#    paste kql/denied-requests.kql into the LAW Logs blade
```

## What each script does

- `prove-public-blocked.sh` runs three calls from **your laptop**:
  - `KV ➜ GET /secrets?api-version=…`
  - `Storage ➜ GET / (list containers)`
  - `AOAI ➜ POST /openai/deployments/gpt-4o-mini/chat/completions`
  - All authenticated with **AAD tokens** (no API keys). On Enforced, the **403 has a `x-ms-error-code: NetworkSecurityPerimeterDenied`** header — that's NSP, not the resource itself.

- `prove-internal-allowed.sh` SSHes to the jump VM and runs the **same calls** with the UAMI token. They succeed.

## KQL

Run [`kql/denied-requests.kql`](kql/denied-requests.kql) after the laptop calls fail. You'll see one row per call with `result_s = "Denied"`, `accessMode_s = "Enforced"`, your source IP, and the resource that denied.
